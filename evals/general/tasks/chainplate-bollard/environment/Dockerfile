# chainplate-bollard — networkx/networkx spanning-tree iterator bug (upstream
# gh-8563; issue ref #8584). Clones the REAL upstream repository at the PARENT
# commit into /app/src via `git init` + one depth-1 fetch of exactly that SHA,
# so the fix commit is never reachable from the trial clone (a belt in the
# verifier asserts `git cat-file -e <fix>^{commit}` fails). Extracts the
# project's own regression test (the test the fix commit appends to
# networkx/algorithms/tree/tests/test_mst.py) from the FIX commit into
# /opt/golden using a throwaway clone that is deleted immediately, and
# digest-checks it against the bytes mined during verification. Installs the
# pinned pytest and the repository editable, then warms the offline trial
# environment: the fail-closed direct-repro check (next() on
# SpanningTreeIterator must raise AttributeError at the parent commit), the
# golden regression nodeid failing at the parent, and the project's own full
# mst test file passing on the pristine parent tree.

ARG UPSTREAM_SHA_PARENT=5d160909eeb42e9844496dd2bbd19b826d2242d7
ARG UPSTREAM_SHA_FIX=46a639aeb9bd4db8da444bd6a532df567b9a73cc

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Single-CPU task: keep any numeric thread pool that appears at one thread so
# nothing oversubscribes the one vCPU (this task itself is pure Python).
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Clone the real upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/networkx/networkx.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression test for this bug (the test the fix
# commit appends to networkx/algorithms/tree/tests/test_mst.py) into
# /opt/golden using a THROWAWAY clone that is deleted immediately afterwards,
# so upstream test bytes never land in this task tree and the fix commit
# never lands in /app/src. Digest-pinned to the bytes verified at authoring.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/networkx/networkx.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:networkx/algorithms/tree/tests/test_mst.py > /opt/golden/test_mst.py \
 && test "$(sha256sum /opt/golden/test_mst.py | awk '{print $1}')" = "985c62908be34305e954fd3f747c65cdac344d2da791841cc1f949725440f132" \
 && grep -q "test_next_without_iter" /opt/golden/test_mst.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Pinned Python dependencies, resolved against the base interpreter.
# pytest==9.1.1 matches the mining pass; numpy/scipy are NOT installed (the
# mst tests that need them skip via pytest.importorskip).
RUN pip install --no-cache-dir pytest==9.1.1 \
 && python -c "import pytest; print('pytest', pytest.__version__)"

# Install the repository editable so `import networkx` resolves to the
# agent's tree at /app/src. The project metadata declares no runtime deps.
# Run the smoke import from /tmp so no build artifacts land in /app.
RUN pip install --no-cache-dir -e /app/src \
 && cd /tmp \
 && python -c "import networkx as nx; print('networkx', nx.__version__, 'from', nx.__file__)"

# FAIL-CLOSED: the mined bug must be present — calling next() directly on a
# SpanningTreeIterator (without iter()) raises AttributeError at the parent
# commit. If upstream ever restores this behaviour differently, the build
# fails instead of shipping a task whose oracle cannot pass.
RUN python - <<'PY'
import networkx as nx
try:
    next(nx.SpanningTreeIterator(nx.cycle_graph(3)))
except AttributeError:
    print("ok: bug present at parent (AttributeError on direct next())")
else:
    raise SystemExit("FAIL: direct next() did NOT raise AttributeError at the parent commit")
PY

# The upstream regression test (as extracted into /opt/golden) FAILS against
# this parent tree — proves the golden bytes target the mined defect.
RUN python -m pytest '/opt/golden/test_mst.py::TestSpanningTreeIterator::test_next_without_iter' \
        -q -p no:cacheprovider > /tmp/golden_at_parent.log 2>&1 || true \
 && grep -q "1 failed" /tmp/golden_at_parent.log \
 && echo "ok: golden regression test fails at parent (1 failed)"

# Warm: the project's own existing mst test file passes on the PRISTINE
# parent tree (no existing test covers the direct-next() entry path, so the
# pre-existing suite is green). Run from /app/src so pytest's rootdir picks
# up the tree; caches stay out of git via the repo's .gitignore.
WORKDIR /app/src
RUN python -m pytest networkx/algorithms/tree/tests/test_mst.py -q -p no:cacheprovider \
        > /tmp/warm_suite.log 2>&1 \
 && tail -1 /tmp/warm_suite.log \
 && grep -q "passed" /tmp/warm_suite.log

# The image is built as root; the trial may run as root or as uid 1000.
# Make the tree writable by uid 1000 from the start.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true

COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]