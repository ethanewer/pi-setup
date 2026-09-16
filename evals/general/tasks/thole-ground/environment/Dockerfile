# thole-ground: real upstream defect in werkzeug's float route converter.
# URL generation for extreme float values uses scientific notation (e.g.
# '/1e-05'), which the router's own regex cannot match, so the generated links
# 404. The agent receives the pinned PRE-fix commit and must repair the library
# so every finite float round-trips through build -> match.
#
# The fix commit f88164a is intentionally NEVER fetched into /app/src: main is
# shallow-cloned, the parent commit is fetched by SHA and detached onto, and
# the build then asserts the fix commit's object is absent from the clone, so
# the agent cannot read the answer from git history or git objects.
FROM bench-base:python-3.12

ARG PARENT_SHA=b97e13cc74d8a45dca260d4037edd7d1f5094042
ARG FIX_SHA=f88164a271dd3e86a3241389ddc5c53eca4b9e4a

# Trials may run as uid 1000 over a root-built tree; git refuses to operate
# without a system-wide safe.directory entry. A committer identity lets
# build-time and trial-time commits work.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone main shallow, fetch the exact parent commit by SHA, detach onto it.
# Fail closed: if upstream moves or the pin vanishes, the asserts die. The
# ownership change shares this RUN so no extra copy-on-write layer is created.
RUN git clone --depth 1 https://github.com/pallets/werkzeug.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin "$PARENT_SHA" \
 && git checkout -q "$PARENT_SHA" \
 && test "$(git rev-parse HEAD)" = "$PARENT_SHA" \
 && { if git cat-file -e "$FIX_SHA^{commit}" 2>/dev/null; then \
       echo "FIX COMMIT OBJECT PRESENT IN WORKING CLONE - refusing to build"; exit 1; \
     else \
       echo "fix commit object not reachable from /app/src (confirmed)"; \
     fi; } \
 && chmod -R a+rwX /app/src

# Dependency pins from the mining entry (resolved against bench-base
# python-3.12): pytest-xprocess is imported by tests/conftest.py even for a
# single-test collection; ephemeral-port-reserve and watchdog back the server
# tests. MarkupSafe resolves from the editable install, unversioned.
RUN pip install --no-cache-dir -e /app/src \
        pytest==9.1.1 \
        pytest-timeout==2.4.0 \
        pytest-xprocess==1.0.2 \
        cffi==2.1.1 \
        cryptography==50.0.1 \
        ephemeral-port-reserve==1.1.4 \
        watchdog==6.0.0

# Extract the project's OWN regression test from the FIX commit through a
# separate throwaway clone under /tmp, which is deleted afterwards so the fix
# object never enters the shipped repository. Then prove it FAILS at the
# parent, so the build also fails closed if the bug is not actually present.
RUN <<EOF
set -eu
git clone --depth 1 https://github.com/pallets/werkzeug.git /tmp/goldclone
cd /tmp/goldclone
git fetch --depth 1 origin "$FIX_SHA"
git checkout -q "$FIX_SHA"
test "$(git rev-parse HEAD)" = "$FIX_SHA"
mkdir -p /opt/golden
python3 - <<'PY'
import ast
src = open('/tmp/goldclone/tests/test_routing.py', encoding='utf-8').read()
tree = ast.parse(src)
node = next(n for n in tree.body
            if isinstance(n, ast.FunctionDef)
            and n.name == 'test_float_no_scientific')
body = ast.get_source_segment(src, node)
open('/opt/golden/test_float_no_scientific.py', 'w', encoding='utf-8').write(
    'import werkzeug.routing as r\n\n' + body + '\n')
PY
rm -rf /tmp/goldclone
test ! -e /tmp/goldclone
cd /app/src
if python3 -m pytest /opt/golden/test_float_no_scientific.py -q -p no:cacheprovider >/tmp/golden_at_parent.log 2>&1; then
    echo "GOLDEN TEST PASSES AT PARENT - BUG NOT PRESENT, refusing to build"
    exit 1
else
    echo "golden test fails at parent (bug present, as required)"
fi
EOF

# A pristine, root-owned, read-only copy of the PRE-fix tree for the verifier
# to run the agent's reproduction and the golden test against. Byte-identical
# to what /app/src started as; the verifier checks its integrity.
RUN cp -a /app/src /opt/pristine \
 && chmod -R a-w /opt/pristine \
 && test "$(git -C /opt/pristine rev-parse HEAD)" = "$PARENT_SHA"

# Snapshot of the pristine test-suite bytes so the verifier can prove the
# agent did not delete or edit tests to make the suite green.
RUN cd /app/src \
 && find tests -type f ! -name '*.pyc' ! -path '*/__pycache__/*' -print0 \
      | sort -z | xargs -0 sha256sum > /opt/tests.sha256

# The full upstream suite must already be green at the parent (983 tests,
# ~8 s), so a build that cannot reproduce that baseline (e.g. a wrong pytest
# for this tree) dies here instead of at trial time.
RUN cd /app/src && python3 -m pytest -q -p no:cacheprovider >/tmp/full0.log 2>&1 \
 && tail -n 2 /tmp/full0.log

ENV PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

WORKDIR /app
CMD ["/bin/bash"]