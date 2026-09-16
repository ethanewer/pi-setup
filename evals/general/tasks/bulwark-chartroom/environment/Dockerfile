# bulwark-chartroom: falconry/falcon, upstream-clone debugging task.
#
# Upstream issue #2667 (fix PR #2682, fix commit ce0a35b8fd02747cc72710202886874906b0d47a):
# `Request.root_path` returns the WSGI SCRIPT_NAME verbatim without the
# PEP 3333 latin-1 tunnel decoding that is applied to PATH_INFO, so an app
# mounted under a non-ASCII URL prefix reports a mojibake root path.
#
# The image clones falconry/falcon SHALLOW at the PARENT commit (the real bug
# is present in the working tree), extracts the project's own regression test
# for the bug from the FIX commit at build time into /opt/golden/ (upstream
# bytes never enter this repository), bakes a pristine PRE-FIX tree at
# /opt/prefix-src for the verifier's concept runs, and proves BOTH directions
# inside this image with the pinned dependency versions before shipping.
# The fix commit is a descendant of the parent, so it is NOT reachable from
# the depth-1 clone the agent works on; the extraction uses a throwaway clone
# under /tmp that is deleted, so the fix objects never enter /app/src.
#
# Pure Python, no compiled extensions (falcon's setup.py builds a plain
# editable wheel), no network at trial time.
#
# NOTE: buildkit allows at most ONE heredoc per RUN, at the end of the
# instruction. Runs that need several multi-line inputs use a single python3
# heredoc that writes its files and runs the proofs via subprocess.

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=1ae55f7d46f1f210550972366ee68fc62cd9f3d9
ARG UPSTREAM_SHA_FIX=ce0a35b8fd02747cc72710202886874906b0d47a

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---------------------------------------------------------------------------
# Working clone: shallow, detached onto the pinned PARENT commit. Fail closed
# if upstream ever moves; the fix commit (and any descendant of it) must not
# be reachable from, nor readable inside, /app/src. We therefore git init and
# fetch ONLY the bare parent SHA: a plain clone would drag in the current
# master tip (and refs/remotes/origin/*), and that tip is a descendant of the
# fix, so the fixed bytes would be one `git show refs/remotes/origin/master:`
# away. Fetching a bare SHA creates no refs and packs only the parent's
# objects, so neither the fix commit object nor the master tip is addressable.
# ---------------------------------------------------------------------------
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA_PARENT" \
 && ! git cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" \
 && git config --system --add safe.directory '/app/src' \
 && git log --oneline -1

# ---------------------------------------------------------------------------
# Extract the project's OWN regression test for this bug from the FIX commit,
# through a throwaway clone under /tmp (deleted inside this same RUN), so the
# fix objects never exist inside /app/src/.git.
# ---------------------------------------------------------------------------
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git show ${UPSTREAM_SHA_FIX}:tests/test_request_attrs.py > /tmp/reqattrs_fix.py \
 && mkdir -p /opt/golden \
 && python3 - <<'PYEOF'
import re
src = open('/tmp/reqattrs_fix.py', encoding='utf-8').read()
m = re.search(r'(?ms)^def test_root_path_non_ascii_wsgi.*?(?=^(?:def|class) |\Z)', src)
assert m, 'golden test not found in the fix commit'
body = m.group(0).rstrip() + '\n'
out = (
    '# Extracted at image build time from the upstream fix commit\n'
    '# (falconry/falcon ce0a35b8fd02747cc72710202886874906b0d47a)\n'
    "# tests/test_request_attrs.py - the project's own regression test.\n"
    'import falcon.testing as testing\n'
    'from falcon import Request\n'
    '\n'
    '\n' + body
)
dest = '/opt/golden/test_root_path_non_ascii_wsgi.py'
open(dest, 'w', encoding='utf-8').write(out)
assert 'def test_root_path_non_ascii_wsgi' in out
assert 'assert req.root_path' in out
assert "'/caf" in out
print('golden test extracted:', dest)

# The throwaway fix clone and the full upstream test file must NOT survive
# in the image: the fix commit would otherwise be one `git -C /tmp/fixsrc
# show` away for the agent. Delete them in this same layer.
import shutil, os
shutil.rmtree('/tmp/fixsrc', ignore_errors=True)
for leftover in ('/tmp/reqattrs_fix.py',):
    try:
        os.remove(leftover)
    except FileNotFoundError:
        pass
assert not os.path.exists('/tmp/fixsrc') and not os.path.exists('/tmp/reqattrs_fix.py')
print('throwaway fix clone deleted; no fix objects remain in the image')
PYEOF

# ---------------------------------------------------------------------------
# Install (editable, from the pinned tree; warm every cache at build time).
# Also warm the project's own full test suite ONCE at the parent commit - it
# must be green here, and the run leaves warm pyc caches for the trial.
# ---------------------------------------------------------------------------
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

RUN cd /app/src \
 && pip install pytest==8.3.4 \
 && pip install -e . \
 && python3 -m pytest tests/ -q -p no:cacheprovider > /tmp/warm-suite.log 2>&1; rc=$?; \
    tail -3 /tmp/warm-suite.log; \
    if [ $rc -ne 0 ]; then echo "BUILD FAILED: full suite not green at the parent commit (exit $rc)"; exit 1; fi; \
    rm -f /tmp/warm-suite.log \
 && chmod -R a+rwX /app/src

# ---------------------------------------------------------------------------
# FAIL-direction proofs inside THIS image: bake the pristine pre-fix concept
# tree and prove the reported symptom (and the golden regression test, and
# hidden-case inputs) reproduce against it with the pinned dependency
# versions. The proof scripts live under /tmp and are deleted later.
# ---------------------------------------------------------------------------
RUN python3 - <<'PYEOF'
import os, shutil, subprocess, sys

def run(argv, cwd=None):
    p = subprocess.run(argv, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr

def check(name, cond, out):
    if not cond:
        sys.stderr.write('BUILD FAILED: ' + name + '\n' + (out or '') + '\n')
        sys.exit(1)

SP = run(['python3', '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))'])[1].strip()
assert SP and os.path.isdir(SP), 'site-packages not resolved'

open('/tmp/launch.py', 'w').write(
    'import sys\n'
    'tree, script = sys.argv[1], sys.argv[2]\n'
    "sys.path[:0] = [tree]\n"
    "exec(compile(open(script, encoding='utf-8').read(), script, 'exec'))\n"
)
open('/tmp/pylaunch.py', 'w').write(
    'import sys\n'
    'tree, sp = sys.argv[1], sys.argv[2]\n'
    "sys.path[:0] = [tree, sp]\n"
    'import pytest\n'
    'raise SystemExit(pytest.main(sys.argv[3:]))\n'
)
open('/tmp/repro_check.py', 'w').write(
    "from falcon import testing, Request\n"
    "\n"
    'PREFIX = "/caf\\u00e9"  # an app mounted under a non-ASCII URL prefix\n'
    "\n"
    "env = testing.create_environ()\n"
    "# A PEP 3333 WSGI server hands the mount prefix to the app with its UTF-8\n"
    '# bytes re-decoded one code point at a time (the latin-1 "tunnel").\n'
    'env["SCRIPT_NAME"] = PREFIX.encode().decode("iso-8859-1")\n'
    'req = Request(env)\n'
    'observed = req.root_path\n'
    'print("observed root_path:", repr(observed))\n'
    'raise SystemExit(0 if observed == PREFIX else 1)\n'
)
open('/tmp/hc_check.py', 'w').write(
    'import falcon.testing as testing\n'
    'from falcon import Request\n'
    '\n'
    '\n'
    'def _check(prefix):\n'
    "    env = testing.create_environ()\n"
    "    env['SCRIPT_NAME'] = prefix.encode().decode('iso-8859-1')\n"
    '    req = Request(env)\n'
    "    assert req.root_path == prefix, '%r != %r' % (req.root_path, prefix)\n"
    '\n'
    '\n'
    'def test_cyrillic_prefix():\n'
    "    _check('/\\u043f\\u0440\\u043e\\u0434\\u0430\\u0436\\u0438')  # /продажи\n"
    '\n'
    '\n'
    'def test_euro_sign():\n'
    "    _check('/\\u20ac')  # /EUR (3-byte UTF-8 character)\n"
    '\n'
    '\n'
    'def test_multi_byte_emoji():\n'
    "    _check('/\\U0001f30d')  # /globe (4-byte UTF-8 character)\n"
    '\n'
    '\n'
    'def test_invalid_utf8_bytes():\n'
    '    env = testing.create_environ()\n'
    "    env['SCRIPT_NAME'] = '/caf\\xa9'\n"
    '    req = Request(env)\n'
    "    assert req.root_path == '/caf\\ufffd', repr(req.root_path)\n"
)

PREFIX = '/opt/prefix-src'
os.makedirs(PREFIX, exist_ok=True)
rc, out = run(['bash', '-c', 'git -C /app/src archive HEAD | tar -x -C /opt/prefix-src'])
check('git archive failed', rc == 0, out)
rc, out = run(['bash', '-c', 'find /opt/prefix-src -type d -exec chmod 555 {} + && find /opt/prefix-src -type f -exec chmod 444 {} +'])
check('prefix chmod failed', rc == 0, out)

GOLDEN = '/opt/golden/test_root_path_non_ascii_wsgi.py'
HC = '/tmp/hc_check.py'

print('--- fail direction: conforming repro on pre-fix tree (must FAIL)')
rc, out = run(['python3', '-I', '-S', '/tmp/launch.py', PREFIX, '/tmp/repro_check.py'])
check('conforming repro PASSED on the pre-fix tree', rc != 0, out)
check('repro did not print the observed value on the pre-fix tree', 'observed root_path' in out, out)

print('--- fail direction: golden test on pre-fix tree (must FAIL)')
rc, out = run(['python3', '-I', '-S', '/tmp/pylaunch.py', PREFIX, SP, GOLDEN, '-q', '-p', 'no:cacheprovider'])
check('golden test PASSED on the pre-fix tree', rc != 0, out)
check('golden test failure mode unexpected on the pre-fix tree', '1 failed' in out, out)

print('--- fail direction: hidden-case inputs on pre-fix tree (must FAIL)')
rc, out = run(['python3', '-I', '-S', '/tmp/pylaunch.py', PREFIX, SP, HC, '-q', '-p', 'no:cacheprovider'])
check('hidden-case inputs PASSED on the pre-fix tree', rc != 0, out)
check('hidden-case failure mode unexpected on the pre-fix tree', '4 failed' in out, out)

print('FAIL directions confirmed inside this image')
PYEOF

# ---------------------------------------------------------------------------
# FIX-direction proof inside THIS image: apply the same change to a scratch
# copy of the pre-fix tree under /tmp and require repro + golden + hidden
# inputs + the full project suite to pass. Scratch is deleted in this RUN.
# ---------------------------------------------------------------------------
RUN python3 - <<'PYEOF'
import os, shutil, subprocess, sys

def run(argv, cwd=None):
    p = subprocess.run(argv, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr

def check(name, cond, out):
    if not cond:
        sys.stderr.write('BUILD FAILED: ' + name + '\n' + (out or '') + '\n')
        sys.exit(1)

SP = run(['python3', '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))'])[1].strip()
FIXED = '/tmp/fixedsrc'
shutil.copytree('/opt/prefix-src', FIXED)
rc, out = run(['chmod', '-R', 'u+w', FIXED])
check('chmod scratch failed', rc == 0, out)

path = os.path.join(FIXED, 'falcon', 'request.py')
src = open(path, encoding='utf-8').read()
old = (
    "            # TODO(0xMattB): Implement advanced typing to type as 'str' (see PR #2599)\n"
    "            return self.env['SCRIPT_NAME']  # type: ignore[no-any-return]\n"
)
new = (
    "            root_path: str = self.env['SCRIPT_NAME']\n"
    "            if not root_path.isascii():\n"
    "                root_path = root_path.encode('iso-8859-1').decode('utf-8', 'replace')\n"
    "            return root_path\n"
)
assert old in src, 'fix target not found in scratch tree'
open(path, 'w', encoding='utf-8').write(src.replace(old, new, 1))
print('scratch fix applied')

GOLDEN = '/opt/golden/test_root_path_non_ascii_wsgi.py'
HC = '/tmp/hc_check.py'

print('--- fix direction: conforming repro on fixed scratch tree (must PASS)')
rc, out = run(['python3', '-I', '-S', '/tmp/launch.py', FIXED, '/tmp/repro_check.py'])
check('conforming repro FAILED on the fixed scratch tree', rc == 0, out)
check('repro output missing on fixed scratch tree', 'observed root_path' in out, out)

print('--- fix direction: golden test on fixed scratch tree (must PASS)')
rc, out = run(['python3', '-I', '-S', '/tmp/pylaunch.py', FIXED, SP, GOLDEN, '-q', '-p', 'no:cacheprovider'])
check('golden test FAILED on the fixed scratch tree', rc == 0 and '1 passed' in out, out)

print('--- fix direction: hidden-case inputs on fixed scratch tree (must PASS)')
rc, out = run(['python3', '-I', '-S', '/tmp/pylaunch.py', FIXED, SP, HC, '-q', '-p', 'no:cacheprovider'])
check('hidden-case inputs FAILED on the fixed scratch tree', rc == 0 and '4 passed' in out, out)

print('--- fix direction: FULL project suite on fixed scratch tree (must PASS)')
rc, out = run(['python3', '-I', '-S', '/tmp/pylaunch.py', FIXED, SP, 'tests/', '-q', '-p', 'no:cacheprovider'], cwd=FIXED)
tail = '\n'.join(out.strip().splitlines()[-2:])
print(tail)
check('full suite FAILED on the fixed scratch tree', rc == 0 and '3786 passed' in out, tail)

shutil.rmtree(FIXED)
print('FIX directions confirmed inside this image')
PYEOF

# ---------------------------------------------------------------------------
# Pins for the verifier's trust anchor: sha256 of the golden test bytes as
# extracted from the upstream fix commit.
# ---------------------------------------------------------------------------
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_root_path_non_ascii_wsgi.py > /opt/pins/pins.sha256 \
 && chmod 555 /opt/golden /opt/pins \
 && chmod 444 /opt/golden/test_root_path_non_ascii_wsgi.py /opt/pins/pins.sha256 \
 && sha256sum -c /opt/pins/pins.sha256 \
 && echo "pins recorded"

# Belt: fix commit unreachable from the trial clone; HEAD exactly the parent.
RUN test "$(git -C /app/src rev-parse HEAD)" = "$UPSTREAM_SHA_PARENT" \
 && if git -C /app/src cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" 2>/dev/null; then echo "ERROR: fix reachable from /app/src"; exit 1; fi \
 && echo "trial tree at $UPSTREAM_SHA_PARENT; fix commit unreachable from /app/src" \
 && rm -f /tmp/launch.py /tmp/pylaunch.py /tmp/repro_check.py /tmp/hc_check.py /tmp/pf_repro.out /tmp/pf_golden.out /tmp/pf_hc.out

WORKDIR /app

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]