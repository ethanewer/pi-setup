#!/bin/bash
# Verifier for olive-quarry (executes-deliverable).
#
# Executes all three deliverables, re-checks the commissioned state, and
# probes hidden cases: unseen kernel names via a temp HOME and unseen R
# package tarballs via a temp library. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json
import os
import subprocess
import sys
import tempfile

HD = '/tests/hidden'
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s  <%s>' % (name, detail))


def run(cmd, env=None, timeout=120):
    return subprocess.run(cmd, capture_output=True, text=True,
                          env=env, timeout=timeout)


def r_env(lib=None, home=None):
    e = dict(os.environ)
    if lib:
        e['R_LIBS'] = lib
    if home:
        e['HOME'] = home
    return e


# ---- execute deliverable /app/setup.sh (twice: must be idempotent) ----
r1 = run(['bash', '/app/setup.sh'])
check('setup_sh_exit0', r1.returncode == 0, (r1.stdout + r1.stderr)[-300:])
r2 = run(['bash', '/app/setup.sh'])
check('setup_sh_idempotent', r2.returncode == 0, (r2.stdout + r2.stderr)[-300:])

# ---- visible state: configured kernel registered and detected ----
exp = json.load(open('/tests/expected.json'))
kname = exp['kernel']['name']
kdisp = exp['kernel']['display']

ks = run(['jupyter', 'kernelspec', 'list', '--json'])
check('jupyter_kernelspec_json_ok', ks.returncode == 0, ks.stderr[-300:])
specs = {}
if ks.returncode == 0:
    try:
        specs = json.loads(ks.stdout).get('kernelspecs', {})
    except Exception as exc:  # noqa: BLE001
        check('kernelspec_json_parse', False, str(exc))
check('visible_kernel_detected', kname in specs, sorted(specs.keys()))
if kname in specs:
    spec = specs[kname].get('spec', {})
    check('visible_kernel_display',
          spec.get('display_name') == kdisp, spec.get('display_name'))
    argv = spec.get('argv', [])
    argv0 = argv[0] if argv else ''
    check('visible_kernel_argv0_exec',
          bool(argv0) and os.path.isfile(argv0) and os.access(argv0, os.X_OK),
          argv0)
    check('visible_kernel_argv0_is_R',
          bool(argv0) and os.path.basename(argv0).startswith('R'), argv0)
kj = '/root/.local/share/jupyter/kernels/%s/kernel.json' % kname
check('visible_kernel_json_file', os.path.isfile(kj), kj)

# IRkernel package must be loadable (never remove/break it)
ir = run(['Rscript', '--vanilla', '-e',
          'suppressMessages(library(IRkernel))'])
check('irkernel_loadable', ir.returncode == 0, ir.stderr[-200:])


def r_checks(lib, pkg, checks, tag):
    for i, c in enumerate(checks):
        code = ("suppressMessages(library(%s)); got <- (%s); "
                "cat(paste(as.character(got), collapse='\\x1f'))"
                % (pkg, c['expr']))
        r = run(['Rscript', '--vanilla', '-e', code],
                env=r_env(lib=lib))
        if r.returncode != 0:
            check('%s_%d' % (tag, i), False, r.stderr[-200:])
            continue
        got = r.stdout.split('\x1f') if r.stdout != '' else []
        check('%s_%d' % (tag, i), got == c['expected'],
              (c['expr'], got, c['expected']))


# ---- visible state: vendored causal packages installed with results intact
for pkg, checks in exp['packages'].items():
    code = 'suppressMessages(library(%s))' % pkg
    r = run(['Rscript', '--vanilla', '-e', code])
    check('visible_pkg_%s_loads' % pkg, r.returncode == 0, r.stderr[-200:])
    r_checks(None, pkg, checks, 'visible_%s' % pkg)

# ---- execute deliverable /app/register_kernel.sh on HIDDEN kernel cases ----
if os.path.isfile('/app/register_kernel.sh'):
    try:
        cases = json.load(open(os.path.join(HD, 'kernel_cases.json')))
    except Exception as exc:  # noqa: BLE001
        cases = []
        check('kernel_cases_parse', False, str(exc))
    for c in cases:
        name, disp = c['name'], c['display']
        tmp = tempfile.mkdtemp(prefix='khome_')
        r = run(['bash', '/app/register_kernel.sh', name, disp, tmp])
        check('hidden_kernel_%s_exit0' % name, r.returncode == 0,
              (r.stdout + r.stderr)[-300:])
        kj_path = os.path.join(tmp, '.local/share/jupyter/kernels', name,
                               'kernel.json')
        check('hidden_kernel_%s_json' % name, os.path.isfile(kj_path), kj_path)
        if os.path.isfile(kj_path):
            try:
                spec = json.load(open(kj_path))
                argv0 = spec.get('argv', [''])[0]
                check('hidden_kernel_%s_argv0' % name,
                      os.path.isfile(argv0) and os.access(argv0, os.X_OK)
                      and os.path.basename(argv0).startswith('R'), argv0)
                check('hidden_kernel_%s_display' % name,
                      spec.get('display_name') == disp,
                      spec.get('display_name'))
            except Exception as exc:  # noqa: BLE001
                check('hidden_kernel_%s_parse' % name, False, str(exc))
        # name detection through the jupyter CLI under the temp HOME
        lst = run(['jupyter', 'kernelspec', 'list', '--json'],
                  env=r_env(home=tmp))
        found = False
        if lst.returncode == 0:
            try:
                found = name in json.loads(lst.stdout).get('kernelspecs', {})
            except Exception:
                found = False
        check('hidden_kernel_%s_detected' % name, found, lst.stdout[-200:])

# ---- execute deliverable /app/install_rpkg.sh on HIDDEN package tarballs ----
rpkg_dir = os.path.join(HD, 'rpkg')
if os.path.isfile('/app/install_rpkg.sh'):
    try:
        rp_exp = json.load(open(os.path.join(rpkg_dir, 'expected.json')))
    except Exception as exc:  # noqa: BLE001
        rp_exp = {}
        check('rpkg_expected_parse', False, str(exc))
    for pkg, checks in rp_exp.items():
        # tarball version is unknown to the verifier: glob for it
        import glob
        cands = sorted(glob.glob(os.path.join(rpkg_dir, pkg + '_*.tar.gz')))
        if not cands:
            check('hidden_pkg_%s_tarball' % pkg, False, pkg)
            continue
        tarball = cands[0]
        tmp = tempfile.mkdtemp(prefix='rlib_')
        r = run(['bash', '/app/install_rpkg.sh', tarball, tmp])
        check('hidden_pkg_%s_install_exit0' % pkg, r.returncode == 0,
              (r.stdout + r.stderr)[-300:])
        # reinstall must also succeed (idempotent installer)
        r2 = run(['bash', '/app/install_rpkg.sh', tarball, tmp])
        check('hidden_pkg_%s_reinstall_exit0' % pkg, r2.returncode == 0,
              (r2.stdout + r2.stderr)[-300:])
        r_checks(tmp, pkg, checks, 'hidden_%s' % pkg)

# ---- deliverables exist ----
for d in ('/app/setup.sh', '/app/register_kernel.sh', '/app/install_rpkg.sh'):
    check('deliverable_%s' % d, os.path.isfile(d) and os.access(d, os.X_OK), d)

print('verify failures:', probs)
sys.exit(1 if probs else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
