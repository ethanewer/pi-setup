# limber-cinder: clone pallets/jinja at the PARENT commit of jinja issue
# #1448 and have the agent reproduce/fix the membership-on-undefined
# regression in the real tree.
#
# The trial receives the real upstream tree at the parent commit (bug
# intact) through an editable install, must author its own failing
# reproduction (/app/repro.py), then fix the defect in the tree. The
# verifier runs the agent's reproduction against this tree (must pass) and
# against a pristine PRE-FIX copy baked here (must fail), replants the
# project's own regression test (the fix commit's updated
# tests/test_api.py) over the tree's copy and requires it to pass, runs the
# previously-existing suite, and runs four authored hidden cases.

ARG UPSTREAM_SHA_PARENT=189132094135d4c84414404c3b388500d35dc49e
ARG UPSTREAM_SHA_FIX=d5f49f5cc135f1a78704dba7db8212be2388b50e

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository (pallets/jinja) at exactly the parent
# commit with the shallowest possible history: `git init` + one depth-1
# fetch of the pinned SHA means the object store in /app/src holds ONLY the
# parent commit. The fix commit is NEVER fetched into this clone; it is
# asserted unreachable below. The chown happens in the SAME RUN as the
# clone so ownership never forces a second copy of the tree into a new
# layer.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pallets/jinja.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && chown -R 1000:1000 /app/src

# Editable install with the mining run's dependency pins. pytest must stay
# < 8: this commit's tests use the callable form of pytest.raises that
# pytest 8 removed. The installer writes a plain .pth file (pallets/jinja
# at this commit still builds with legacy setuptools, so no PEP 660 meta
# path finder is generated), which means a PYTHONPATH override - the
# verifier's pre-fix lens below - takes precedence over the editable path.
RUN cd /app/src \
 && python3 -m pip install --no-cache-dir -e . 'pytest==7.4.3' 'MarkupSafe==3.0.3' \
 && python3 -c "import jinja2, markupsafe, pytest; assert jinja2.__file__.startswith('/app/src/src'), jinja2.__file__; print('jinja2', jinja2.__version__, 'markupsafe', markupsafe.__version__, 'pytest', pytest.__version__)"

# Bake a pristine PRE-FIX copy of the jinja2 package (the parent commit's
# own source, never touched by the agent) at /opt/pre-fix-jinja. The
# verifier runs the agent's reproduction against this copy via PYTHONPATH
# and requires it to FAIL, proving the symptom is real and that the
# reproduction targets it. Verified importable and buggy right here (fail
# closed).
RUN mkdir -p /opt/pre-fix-jinja \
 && cp -r /app/src/src/jinja2 /opt/pre-fix-jinja/ \
 && PYTHONPATH=/opt/pre-fix-jinja python3 - <<'PY'
import jinja2
assert jinja2.__file__.startswith('/opt/pre-fix-jinja'), jinja2.__file__
from jinja2 import Environment
try:
    Environment().from_string('{{ "foo" in missing }}').render()
except Exception as e:
    if type(e).__name__ == 'UndefinedError' and 'missing' in str(e):
        print('pre-fix copy reproduces the bug: membership on undefined raises UndefinedError')
    else:
        raise SystemExit('unexpected exception: %r' % (e,))
else:
    raise SystemExit('pre-fix copy did NOT raise on membership - build must fail')
PY

# Extract the project's own regression test for this bug (the fix commit's
# updated tests/test_api.py, where test_default_undefined asserts
# `{{ 'foo' in missing }}` renders "False" and test_strict_undefined asserts
# strict-undefined membership still raises) into /opt/golden using a
# THROWAWAY clone under /tmp that is deleted immediately afterwards, so the
# fix commit never lands in /app/src and no upstream test bytes enter this
# task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/pallets/jinja.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/test_api.py > /opt/golden/test_api.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && python3 - <<'PY'
s = open('/opt/golden/test_api.py', encoding='utf-8').read()
n = s.count("{{ 'foo' in missing }}")
assert n >= 2, "expected both the default and the strict membership assertions, found %d" % n
assert 'render() == "False"' in s, "expected the default-undefined membership assertion"
print("golden test_api.py holds %d membership assertions (default + strict)" % n)
PY

# Parent direction, confirmed in THIS image: the project's own regression
# test for this bug must FAIL on the shipped parent tree (the template in it
# raises UndefinedError instead of rendering "False"). The installed package
# IS this tree (editable install), so pytest runs the planted test file
# against the shipped source.
RUN cd /app/src \
 && python3 -m pytest /opt/golden/test_api.py::TestUndefined::test_default_undefined -q -p no:cacheprovider > /tmp/parent-golden.log 2>&1; rc=$?; \
    tail -6 /tmp/parent-golden.log; \
    if [ $rc -eq 0 ]; then echo "GOLDEN PASSED ON THE SHIPPED TREE - BAD"; exit 1; fi; \
    grep -q "UndefinedError" /tmp/parent-golden.log || { echo "UndefinedError not observed at parent"; exit 1; } \
 && echo "parent direction: golden regression test FAILS on the shipped tree (bug present)"

# Baseline, fail closed: the previously-existing suite (every test file that
# is green in this environment, i.e. all except the two era-broken files
# tests/test_debug.py and tests/test_loader.py) must pass on the pristine
# parent tree, so the verifier's "prove the fix broke nothing else" run has
# a real baseline. These tests are self-contained (measured green with
# --network none).
RUN cd /app/src && python3 -m pytest tests/test_api.py tests/test_async.py tests/test_async_filters.py tests/test_bytecode_cache.py tests/test_compile.py tests/test_core_tags.py tests/test_features.py tests/test_filters.py tests/test_idtracking.py tests/test_imports.py tests/test_inheritance.py tests/test_lexnparse.py tests/test_nativetypes.py tests/test_regression.py tests/test_runtime.py tests/test_security.py tests/test_tests.py tests/test_utils.py -q -p no:cacheprovider > /tmp/baseline.log 2>&1; rc=$?; \
    tail -3 /tmp/baseline.log; \
    if [ $rc -ne 0 ]; then echo "PARENT BASELINE SUITE NOT GREEN (exit $rc)"; tail -40 /tmp/baseline.log; exit 1; fi; \
    grep -q "732 passed" /tmp/baseline.log || { echo "baseline did not report 732 passed"; exit 1; } \
 && echo "baseline: 732 passed on the pristine parent tree"

# Fix direction, confirmed in THIS image against a THROWAWAY checkout of
# the fix commit (deleted immediately afterwards, never shipped): the
# planted regression tests pass and the direct reproduction renders False.
RUN git init -q /tmp/fix-src \
 && cd /tmp/fix-src \
 && git remote add origin https://github.com/pallets/jinja.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && PYTHONPATH=/tmp/fix-src/src python3 -m pytest /opt/golden/test_api.py::TestUndefined::test_default_undefined /opt/golden/test_api.py::TestUndefined::test_strict_undefined -q -p no:cacheprovider > /tmp/fix-golden.log 2>&1; rc=$?; \
    tail -4 /tmp/fix-golden.log; \
    if [ $rc -ne 0 ]; then echo "GOLDEN FAILED ON THE FIX TREE - BAD"; exit 1; fi; \
    grep -q "2 passed" /tmp/fix-golden.log || { echo "golden did not report 2 passed at fix"; exit 1; } \
 && PYTHONPATH=/tmp/fix-src/src python3 -c "from jinja2 import Environment; assert Environment().from_string('{{ \"foo\" in missing }}').render() == 'False'" \
 && cd / && rm -rf /tmp/fix-src \
 && echo "fix direction: golden + direct repro PASS on the fix commit source"

# Belt: prove the fix commit is not reachable from the trial clone and that
# HEAD is still the pinned parent commit (the object store holds exactly
# one commit - the parent - so the fix commit object and every blob it
# changed are absent).
RUN cd /app/src \
 && { git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null && echo "ERROR: fix commit is reachable from /app/src" && exit 1 || true; } \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && echo "fix commit unreachable; HEAD = $(git rev-parse HEAD); working tree clean"

# Record sha256 pins of the golden test, of the pristine pre-fix package
# (whole-file manifest), of the Python/pytest toolchain, and of the
# whole site-packages tree (names AND hashes, so an added file is caught
# too; __pycache__ regenerable bytecode is excluded), so the verifier can
# detect substitution - including the interpreter-level startup-hook
# vector (sitecustomize/usercustomize in site-packages, or a created
# user site) that could shadow the tree's behaviour without touching
# /app/src. /opt is read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_api.py > /opt/pins/golden.sha256 \
 && ( cd / && find /opt/pre-fix-jinja -type f -print0 | sort -z | xargs -0 sha256sum > /opt/pins/pre-fix-manifest.sha256 ) \
 && test -s /opt/pins/pre-fix-manifest.sha256 \
 && sha256sum /usr/local/bin/python3 /usr/local/bin/python3.12 /usr/local/bin/pytest > /opt/pins/toolchain.sha256 \
 && ( find /usr/local/lib/python3.12/site-packages -type f ! -path "*/__pycache__/*" -print0 | sort -z | xargs -0 sha256sum > /opt/pins/site-packages.sha256 ) \
 && test -s /opt/pins/site-packages.sha256 \
 && ( python3 -c "import sitecustomize" >/dev/null 2>&1 && { echo "sitecustomize present at build time - BAD"; exit 1; } || true ) \
 && ( python3 -c "import usercustomize" >/dev/null 2>&1 && { echo "usercustomize present at build time - BAD"; exit 1; } || true ) \
 && test ! -e /root/.local \
 && chmod -R a+rX /opt/pre-fix-jinja \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/test_api.py \
 && ( cd / && sha256sum -c /opt/pins/pre-fix-manifest.sha256 > /dev/null ) \
 && sha256sum -c /opt/pins/golden.sha256 > /dev/null \
 && echo "golden + pre-fix copy + toolchain + site-packages pinned"

# Hand the agent a writable workdir. /app/src is already owned by uid 1000
# (from the clone RUN); /app itself must be writable by the agent too.
COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README.md

WORKDIR /app
CMD ["/bin/bash"]