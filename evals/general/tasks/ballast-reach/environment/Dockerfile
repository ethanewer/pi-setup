# ---------------------------------------------------------------------------
# ballast-reach: pypa/setuptools, MANIFEST.in exclusion rules silently leak
# non-ASCII-named files whose on-disk name differs from the rule's text only
# in Unicode normalization form (NFC vs NFD).
#
# The image clones the REAL upstream repository and checks out the PARENT
# commit (immediately before the upstream fix), so the agent gets the real
# project with the real bug still in it. All dependencies are preinstalled
# and every cache is warm; the trial runs with no network.
# ---------------------------------------------------------------------------
ARG UPSTREAM_SHA=84ed5913724df5a12dc804e1d5efe12508e706d2
ARG UPSTREAM_SHA_FIX=dd9f436a36486b4cb8a4c70a2321548b0be09b8f

FROM bench-base:python-3.12

ARG UPSTREAM_SHA
ARG UPSTREAM_SHA_FIX

# Keep pytest's cache dir and Python bytecode OUT of /app/src so the graded
# tree's untracked-file provenance check is not tripped by the agent's own
# test runs (the repository has no committed .gitignore).
ENV PYTHONPYCACHEPREFIX=/tmp/pycache \
    PYTEST_ADDOPTS="-p no:cacheprovider -o cache_dir=/tmp/pytest_cache" \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# The real upstream tree, checked out at the buggy PARENT commit and pinned
# to the immutable 40-hex revision. Shallowest possible history: `git init`
# plus one depth-1 fetch of exactly the pinned SHA means the object store in
# /app/src holds ONLY the parent commit. The fix commit (which an agent must
# not be able to look up or fetch) is never fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pypa/setuptools.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's OWN regression tests for this bug (upstream added
# them to setuptools/tests/test_manifest.py with the fix) into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so
# upstream test bytes never land in this task tree and the fix commit never
# lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/pypa/setuptools.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:setuptools/tests/test_manifest.py > /opt/golden/test_manifest.py \
 && test -s /opt/golden/test_manifest.py \
 && grep -q "test_translate_pattern_unicode_normalization" /opt/golden/test_manifest.py \
 && grep -q "test_global_exclude_unicode_normalization" /opt/golden/test_manifest.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && chmod a+r /opt/golden/test_manifest.py

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}"

# Project install, exactly the recipe the mining run validated: editable
# install with the project's own [test] extra (so edits to /app/src are
# immediately live), coverage (the repo's pytest.ini warning filter
# references the coverage module), and the pytest version this tree is
# green on (a newer pytest makes collection abort under the repo's
# error-on-warnings filter). Everything is pinned; the trial has no network
# and needs none. deps-pinned.txt freezes the COMPLETE environment at the
# versions the mining run measured, so a rebuild of this Dockerfile is
# byte-deterministic: that is what makes the committed runtime-fingerprint
# (tests/runtime-fingerprint.txt) valid for every future trial.
COPY files/deps-pinned.txt /app/deps-pinned.txt
COPY files/ /app/
RUN cd /app/src \
 && pip install --no-cache-dir -e '.[test]' \
 && pip install --no-cache-dir coverage==7.16.0 \
 && pip install --no-cache-dir 'pytest==8.4.2' \
 && pip install --no-cache-dir -r /app/deps-pinned.txt

# Runtime-integrity manifest: the SHA-256 of every interpreter, package and
# tool file the trial can run, taken AFTER all installs. The verifier runs
# in the SAME container as the agent (shared verifier), so an agent that
# shims the runtime -- a sitecustomize wrapper, a replaced python3 binary,
# an injected site-packages module, an edited /opt/golden test file --
# instead of fixing /app/src would otherwise sail through the behavioral
# checks with the tree untouched. /opt stays read-only for the agent; the
# verifier compares the recomputed manifest (via the fingerprint committed
# at tests/runtime-fingerprint.txt, re-uploaded fresh from the host at
# verify time and visible to the agent at no point) and rejects any drift.
RUN cd / \
 && { find usr/local/bin usr/local/lib/python3.12 -type f -print0 \
      | sort -z | xargs -0 sha256sum; \
      sha256sum bin/bash usr/bin/git opt/golden/test_manifest.py; } \
      > /opt/runtime.manifest \
 && sort /opt/runtime.manifest -o /opt/runtime.manifest \
 && chmod 444 /opt/runtime.manifest \
 && test -s /opt/runtime.manifest

# Guarantee write access for whatever uid (root or 1000) the trial runs as,
# and leave the tree in a state where the verifier can assert provenance.
# /opt is deliberately left read-only: the golden test bytes and the
# runtime manifest are trust anchors and must not be agent-writable.
WORKDIR /app

RUN chmod -R a+rwX /app