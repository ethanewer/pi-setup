# ballast-overtake — networkx/networkx HITS eigenvector-sign bug (upstream
# gh-8899). Clones the REAL upstream repository at the PARENT commit into
# /app/src via `git init` + one depth-1 fetch of exactly that SHA, so the
# fix commit is never reachable from the trial clone. Extracts the project's
# own regression test (the test the fix commit appends to test_hits.py) from
# the FIX commit into /opt/golden using a throwaway clone that is deleted
# immediately. Installs the pinned Python deps and the repository editable,
# then warms the offline trial environment with a run of the project's own
# link-analysis tests against the pristine parent tree.

ARG UPSTREAM_SHA_PARENT=675034adb14a790336121e4e0f9d8097b880ec41
ARG UPSTREAM_SHA_FIX=31ab6fd7e1e149e887282b83a91752c486d071b6

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Single-CPU task: pin numeric kernels to one thread so LAPACK results are
# deterministic and nothing oversubscribes the one vCPU.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

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
# commit appends to networkx/algorithms/link_analysis/tests/test_hits.py)
# into /opt/golden using a THROWAWAY clone that is deleted immediately
# afterwards, so upstream test bytes never land in this task tree and the
# fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/networkx/networkx.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:networkx/algorithms/link_analysis/tests/test_hits.py > /opt/golden/test_hits.py \
 && test -s /opt/golden/test_hits.py \
 && grep -q "test_hits_numpy_normalized_false_finite" /opt/golden/test_hits.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Pinned Python dependencies, resolved against the base interpreter.
# numpy==2.5.3 is the exact version the bug reproduces against (its bundled
# LAPACK returns the dominant eigenvector of path_graph(3) negated, with a
# zero maximum); pytest==9.1.1 and scipy==1.18.1 match the mining pass.
# scipy is required by the golden test file's module-level importorskip.
RUN pip install --no-cache-dir numpy==2.5.3 scipy==1.18.1 pytest==9.1.1 \
 && python -c "import numpy, scipy, pytest; print('numpy', numpy.__version__, '| scipy', scipy.__version__, '| pytest', pytest.__version__)"

# Install the repository editable so `import networkx` resolves to the
# agent's tree at /app/src. The project metadata declares no runtime deps.
# Run the smoke import from /tmp so no build artifacts land in /app.
RUN pip install --no-cache-dir -e /app/src \
 && cd /tmp \
 && python -c "import networkx as nx; print('networkx', nx.__version__, 'from', nx.__file__)"

# Warm: the project's own link-analysis tests pass on the PRISTINE parent
# tree (the regression test for this bug does not exist yet at this commit,
# so they do pass). Run from /tmp so pytest's own caches stay out of /app.
# This layer is what proves the trial environment is complete and offline.
RUN mkdir -p /tmp/warm && cd /tmp/warm \
 && python -m pytest /app/src/networkx/algorithms/link_analysis/ -q -p no:cacheprovider > /tmp/warm_tests.log 2>&1; rc=$?; \
    tail -3 /tmp/warm_tests.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST RUN FAILED (exit $rc)"; exit $rc; fi

# The image is built as root; the trial may run as root or as uid 1000.
# Make the tree writable by uid 1000 from the start.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true

COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]