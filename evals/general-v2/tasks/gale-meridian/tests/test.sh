#!/bin/bash
# Verifier for gale-meridian (executes-deliverable).
#
# Executes the deliverable /app/provision.sh (twice, to confirm idempotency),
# reads the deliverable /app/workbench_report.json, independently re-checks the
# kernelspec state and R package availability, and EXECUTES the visible notebook
# plus every hidden notebook in /tests/hidden through the registered rcw kernel.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

CONF = '/app/workbench.conf'
PROVISION = '/app/provision.sh'
REPORT = '/app/workbench_report.json'
VISIBLE_NB = '/app/notebooks/visible_check.ipynb'
HD = '/tests/hidden'
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s  <%s>' % (name, detail))


def conf(key):
    for line in open(CONF):
        line = line.strip()
        if line and not line.startswith('#'):
            k, _, v = line.partition('=')
            if k == key:
                return v
    return None


KERNEL = conf('kernel_name')
DISPLAY = conf('display_name')
REQ_PKGS = [p for p in conf('packages').split(',') if p]
check('conf_read', bool(KERNEL and DISPLAY and REQ_PKGS))

# ---- execute deliverable /app/provision.sh (idempotency: run twice) ----
if os.path.isfile(PROVISION):
    for i in (1, 2):
        r = subprocess.run(['bash', PROVISION], capture_output=True, text=True,
                           timeout=240)
        check('provision_run_%d_exit0' % i, r.returncode == 0,
              (r.stdout + r.stderr)[-300:])
else:
    probs.append('provision_sh_missing  </app/provision.sh>')

# ---- independent state: R packages load ----
r = subprocess.run(
    ['Rscript', '--vanilla', '-e',
     'library(data.table); library(jsonlite); library(IRkernel); cat("R_OK")'],
    capture_output=True, text=True, timeout=120)
check('r_packages_load', r.returncode == 0 and 'R_OK' in r.stdout,
      (r.stdout + r.stderr)[-300:])

# ---- independent state: kernelspec integrity ----
r = subprocess.run(['jupyter', 'kernelspec', 'list', '--json'],
                   capture_output=True, text=True, timeout=60)
try:
    specs = json.loads(r.stdout or '{}').get('kernelspecs', {})
except Exception as exc:
    specs = {}
    check('kernelspec_list_json', False, str(exc))
check('kernel_registered', KERNEL in specs, sorted(specs))
for name, spec in specs.items():
    if name == 'python3':
        continue  # stock ipykernel spec shipped with the image
    argv0, resolved, err = None, None, ''
    try:
        kj = os.path.join(spec['resource_dir'], 'kernel.json')
        argv0 = json.load(open(kj))['argv'][0]
        resolved = argv0 if os.path.isabs(argv0) else shutil.which(argv0)
        ok = bool(resolved) and os.path.isfile(resolved) \
            and os.access(resolved, os.X_OK)
    except Exception as exc:
        ok, err = False, ' exc=%r' % exc
    check('kernelspec_integrity_%s' % name, ok,
          'dir=%r argv0=%r -> %r%s' % (spec.get('resource_dir'), argv0,
                                        resolved, err))

# ---- execute deliverable /app/workbench_report.json ----
rver = subprocess.run(
    ['Rscript', '--vanilla', '-e',
     'cat(paste(R.version$major, R.version$minor, sep="."))'],
    capture_output=True, text=True, timeout=60).stdout.strip()
if os.path.isfile(REPORT):
    try:
        rep = json.load(open(REPORT))
        check('report_kernel', rep.get('kernel') == KERNEL, rep.get('kernel'))
        rcw_arg = None
        if KERNEL in specs:
            try:
                rcw_arg = json.load(open(os.path.join(
                    specs[KERNEL]['resource_dir'], 'kernel.json')))['argv'][0]
            except Exception:
                rcw_arg = None
        rep_bin = str(rep.get('r_binary', ''))
        rep_resolved = shutil.which(rep_bin) if rep_bin and \
            not os.path.isabs(rep_bin) else rep_bin
        rcw_resolved = shutil.which(rcw_arg) if rcw_arg and \
            not os.path.isabs(rcw_arg) else rcw_arg
        check('report_r_binary',
              bool(rcw_resolved) and os.path.realpath(rep_resolved or '') ==
              os.path.realpath(rcw_resolved),
              (rep.get('r_binary'), rcw_arg))
        check('report_packages',
              set(REQ_PKGS) <= set(rep.get('packages', [])),
              rep.get('packages'))
        check('report_r_version', rep.get('r_version') == rver,
              (rep.get('r_version'), rver))
    except Exception as exc:
        probs.append('report_unreadable  <%s>' % exc)
else:
    probs.append('workbench_report_missing  </app/workbench_report.json>')


# ---- execute R notebooks through the registered kernel ----
def run_notebook(path, required_markers):
    out_ipynb = None
    try:
        work = tempfile.mkdtemp(prefix='meridian_nb_')
        nb = os.path.join(work, 'nb.ipynb')
        shutil.copy(path, nb)
        out_ipynb = os.path.join(work, 'out.ipynb')
        r = subprocess.run(
            ['jupyter', 'nbconvert', '--to', 'notebook', '--execute',
             '--ExecutePreprocessor.timeout=90',
             '--ExecutePreprocessor.kernel_name=' + (KERNEL or 'rcw'),
             '--output', out_ipynb, nb],
            capture_output=True, text=True, timeout=180)
        if r.returncode != 0 or not os.path.isfile(out_ipynb):
            return 'nbconvert_failed: %s' % (r.stderr or r.stdout)[-300:]
        nb_out = json.load(open(out_ipynb))
        texts = []
        for cell in nb_out.get('cells', []):
            for out in cell.get('outputs', []):
                if out.get('output_type') == 'stream':
                    t = out.get('text')
                    texts.append(''.join(t) if isinstance(t, list)
                                 else str(t))
        text = '\n'.join(texts)
        for m in required_markers:
            if not re.search(re.escape(m), text):
                return 'missing marker %r in %r' % (m, text[-400:])
        return None
    except Exception as exc:
        return 'exception: %s' % exc


if os.path.isfile(VISIBLE_NB):
    err = run_notebook(VISIBLE_NB,
                       ['RCW_VISIBLE_OK', 'SUM a 3', 'SUM b 12',
                        '{"units":5,"groups":2}'])
    check('visible_notebook_executes', err is None, err or '')
else:
    probs.append('visible_notebook_missing')

for case in sorted(os.listdir(HD)):
    nb = os.path.join(HD, case)
    if not nb.endswith('.ipynb'):
        probs.append('hidden_%s_unexpected' % case)
        continue
    if case == 'nb_dt.ipynb':
        markers = ['RCW_DT_OK', 'ROW x 18 3', 'ROW y -4 2', 'ROW z 7 1']
    elif case == 'nb_json.ipynb':
        markers = ['RCW_JSON_OK', 'ALPHA 6', 'BETA p,q',
                   'ROUND {"n":7,"ok":true}']
    elif case == 'nb_both.ipynb':
        markers = ['RCW_BOTH_OK', 'WSUM 25.0', 'NROW 2',
                   '[{"id":2,"tag":"t2"},{"id":3,"tag":"t3"}]']
    else:
        markers = ['RCW_OK']
    err = run_notebook(nb, markers)
    check('hidden_%s_executes' % case, err is None, err or '')

print('verify failures:', probs)
sys.exit(1 if probs else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
