# conduit-anchor: upstream-clone bug-fix task on pytest-dev/pytest.
#
# The REAL upstream repository is cloned SHA-pinned at its PARENT commit (the
# commit just before the fix landed) at image-build time; the fix commit is
# never fetched into this clone. The project's OWN updated regression test for
# the bug (the testing/python/approx.py that landed WITH the fix) is extracted
# into /opt/golden via a throwaway clone that is deleted afterwards, so
# upstream test bytes never land in this task tree and the fix commit is never
# reachable from /app/src. The trial runs with no network; pytest is
# editable-installed, so edits under /app/src/src are live.

ARG UPSTREAM_SHA_PARENT=fbab7c5dfe63a22f545207e8dc163ed61ad51d98
ARG UPSTREAM_SHA_FIX=2c555d62fa2c51ccb0c4c1cdd6243149ce4ffa97

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# git-uid-1000 safety and build identity (agents may want to restore files
# inside the clone with git).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Pinned Python toolchain, resolved against this base image's own interpreter
# (Python 3.12.13). This is the project's own `dev` extra (argcomplete,
# attrs>=19.2, hypothesis>=3.56, mock, requests, setuptools, xmlschema) plus
# the pinned build backend, so the editable build below is deterministic
# with --no-build-isolation.
RUN pip install --no-cache-dir \
    argcomplete==3.7.2 \
    attrs==26.1.0 \
    hypothesis==6.168.0 \
    iniconfig==2.3.0 \
    mock==5.2.0 \
    packaging==26.3 \
    pluggy==1.6.0 \
    pygments==2.21.0 \
    requests==2.34.2 \
    setuptools==84.0.0 \
    setuptools-scm==10.2.3 \
    xmlschema==4.3.2

# Clone the REAL upstream project at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
    && cd /app/src \
    && git remote add origin https://github.com/pytest-dev/pytest.git \
    && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
    && git checkout -q --detach FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Editable install so the agent's edits under /app/src/src are live in a
# fresh interpreter. SETUPTOOLS_SCM_PRETEND_VERSION: the checkout is a single
# detached commit with no tags, so without it setuptools-scm guesses
# "0.1.dev1", which is below the project's OWN minversion and makes the
# project's test suite refuse to run.
RUN cd /app/src \
    && SETUPTOOLS_SCM_PRETEND_VERSION_FOR_PYTEST=9.2.0.dev0 \
       pip install --no-cache-dir --no-build-isolation -e .

# Extract the project's OWN regression test for this bug (the
# testing/python/approx.py state that landed WITH the fix) into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so upstream
# test bytes never land in this task tree and the fix commit never lands in
# /app/src.
RUN git init -q /tmp/upstream-fix-clone \
    && cd /tmp/upstream-fix-clone \
    && git remote add origin https://github.com/pytest-dev/pytest.git \
    && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
    && mkdir -p /opt/golden \
    && git show ${UPSTREAM_SHA_FIX}:testing/python/approx.py > /opt/golden/approx.py \
    && test -s /opt/golden/approx.py \
    && grep -q "test_timedelta_rel_must_be_number" /opt/golden/approx.py \
    && grep -q "test_timedelta_in_sequence" /opt/golden/approx.py \
    && cd / \
    && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is NOT reachable from the trial clone, and the
# trial tree is pristine at the parent commit.
RUN cd /app/src \
    && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
         echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
       fi \
    && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
    && test -z "$(git status --porcelain)"

# Smoke: the project's own python test suite is green on the pristine parent
# tree (this is the same region the verifier asserts on after the agent's
# change). Runs in well under a minute on one CPU.
RUN cd /app/src \
    && (python3 -m pytest testing/python/ -q -p no:cacheprovider > /tmp/smoke.log 2>&1 \
        || { echo "SMOKE TEST FAILED:"; tail -40 /tmp/smoke.log; exit 1; }) \
    && tail -1 /tmp/smoke.log \
    && rm -f /tmp/smoke.log

# Thread-pool pins (the suite is pure Python; keep any extension libs
# single-threaded - the sweep runs one CPU).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# The trial may run as uid 1000; make the clone writable by that user
# (the task requires editing the tree in place).
RUN chown -R 1000:1000 /app/src 2>/dev/null || chmod -R a+rwX /app/src

WORKDIR /app

COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]