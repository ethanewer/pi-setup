# lazaret-careen — networkx/networkx GML tuple-label quote-escaping bug
# (upstream gh-8755). Clones the REAL upstream repository at the PARENT
# commit into /app/src via `git init` + one depth-1 fetch of exactly that
# SHA, so the fix commit is never reachable from the trial clone. Extracts
# the project's own regression test (the test the fix commit adds to
# networkx/readwrite/tests/test_gml.py) from the FIX commit into /opt/golden
# using a throwaway clone that is deleted immediately. Installs the pinned
# test dependency (pytest) and the repository editable, then warms the
# offline trial environment with a run of the project's own GML tests
# against the pristine parent tree.

ARG UPSTREAM_SHA_PARENT=b1f956344071ba1adfad17d56d62a7a78dfd37e6
ARG UPSTREAM_SHA_FIX=304b3ae481c2027f6b6ff493715cdeb7043cb90d

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Single-CPU task: pin numeric kernels to one thread so nothing
# oversubscribes the one vCPU.
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
# commit adds to networkx/readwrite/tests/test_gml.py) into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so
# upstream test bytes never land in this task tree and the fix commit never
# lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/networkx/networkx.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:networkx/readwrite/tests/test_gml.py > /opt/golden/test_gml.py \
 && test -s /opt/golden/test_gml.py \
 && grep -q "test_tuple_label_quote_escape" /opt/golden/test_gml.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Pinned test dependency, resolved against the base interpreter.
# pytest==9.1.1 matches the mining pass. networkx 3.x itself is pure python
# and its GML reader/writer needs only the stdlib, so no numpy/scipy are
# required by anything this task exercises.
RUN pip install --no-cache-dir pytest==9.1.1 \
 && python -c "import pytest; print('pytest', pytest.__version__)"

# Install the repository editable so `import networkx` resolves to the
# agent's tree at /app/src. The project metadata declares no runtime deps.
# Run the smoke import from /tmp so no layer-fattening build artifacts
# land in /app. The warm run then proves the project's own GML tests pass
# on the PRISTINE parent tree (the regression test for this bug does not
# exist yet at this commit, so they do pass) and therefore the trial
# environment is complete and offline. The whole thing is one RUN layer so
# the ownership fix costs nothing extra (see the v4.2 image-size notes).
RUN pip install --no-cache-dir -e /app/src \
 && cd /tmp \
 && python -c "import networkx as nx; print('networkx', nx.__version__, 'from', nx.__file__)" \
 && mkdir -p /tmp/warm && cd /tmp/warm \
 && python -m pytest /app/src/networkx/readwrite/tests/test_gml.py -q -p no:cacheprovider > /tmp/warm_tests.log 2>&1 \
 && tail -3 /tmp/warm_tests.log \
 && chmod -R a+rwX /app/src \
 && chown -R 1000:1000 /app/src

# The image is built as root; the trial may run as root or as uid 1000.
# /app/src was chowned to uid 1000 in the same layer that produced it.
WORKDIR /app
COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]