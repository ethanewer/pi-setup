# bitts-longshore: sympy/sympy issue #28744 - an inner Mod factor is
# duplicated (squared) instead of being dropped when symbolic modulo
# expressions are rebuilt inside Mod.number_eval.
#
# The image clones the REAL upstream repository at exactly the PARENT commit
# (the working tree the agent receives, bug still present) and installs it in
# editable mode, so the code the agent imports is exactly the checked-out
# source and its edits take effect immediately. The project's own regression
# test for the bug is extracted from the FIX commit at image build time into
# /opt/golden/ via a THROWAWAY clone that is deleted immediately afterwards
# (upstream fix bytes never enter this repository and never land in
# /app/src); a pristine copy of the parent's sympy/core/mod.py goes to
# /opt/prefix/ so the verifier can rebuild the pre-fix tree offline.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=648f6cfb88b83e58655499523fb6cede213d10c2
ARG UPSTREAM_SHA_FIX=f1b4be1bf83baee7e9ac116e81cdae1f30c5d1cd

# Base tooling for the clone, plus the mandatory safe.directory guard (the
# trial may run as uid 1000 against a root-created clone).
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable -----------
# A single shallow fetch of the pinned parent SHA means the object store in
# /app/src holds exactly ONE commit (the parent) and no object reachable only
# from the fix. Everything touching /app/src happens in THIS one RUN so the
# layer is written once (no chown copy duplication): clone, editable install,
# pinned test dependencies, a warm pytest run that precompiles the tree's
# bytecode, and a chown to the trial uid at the end.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && python3 -m pip install --no-cache-dir -e . \
 && python3 -m pip install --no-cache-dir mpmath==1.3.0 pytest==9.1.1 hypothesis==6.168.0 \
 && python3 -m pytest 'sympy/core/tests/test_arit.py::test_Mod' -p no:cacheprovider > /tmp/warm.log 2>&1; rc=$?; \
    tail -3 /tmp/warm.log; \
    [ $rc -eq 0 ] || { echo "WARM PYTEST RUN FAILED (exit $rc)"; exit 1; }; \
    test -z "$(git status --porcelain)" \
 && echo "editable install ok, working tree clean, test warm" \
 && chown -R 1000:1000 /app/src \
 && rm -f /tmp/warm.log

# ---- extract the upstream regression test + pristine pre-fix source --------
# A throwaway shallow clone of the FIX commit supplies two things, then is
# deleted so the fix commit never exists inside /app/src/.git:
#   /opt/golden/test_arit.py  - the project's own regression test for this
#                              bug (the fix commit's version of test_Mod),
#                              with the upstream "issue 28744" comment
#                              stripped so the image does not hand the agent
#                              the issue number;
#   /opt/prefix/mod.py        - the parent's pristine sympy/core/mod.py, for
#                              the verifier's pre-fix scratch tree.
# BOTH DIRECTIONS are re-confirmed in THIS image with the pinned dependency
# versions: the golden test must FAIL on a copy of the parent tree and PASS
# on a copy carrying the fixed mod.py. The scratch copies live in /tmp and
# are deleted inside the same RUN, so no bytes are duplicated into layers.
RUN git init -q /tmp/fixclone \
 && cd /tmp/fixclone \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden /opt/prefix \
 && git show ${UPSTREAM_SHA_FIX}:sympy/core/tests/test_arit.py \
      | grep -v 'issue 28744' > /opt/golden/test_arit.py \
 && test -s /opt/golden/test_arit.py \
 && grep -q 'def test_Mod' /opt/golden/test_arit.py \
 && test "$(grep -c '28744' /opt/golden/test_arit.py)" = "0" \
 && git -C /app/src show ${UPSTREAM_SHA_PARENT}:sympy/core/mod.py > /opt/prefix/mod.py \
 && test -s /opt/prefix/mod.py \
 && cp -a /app/src /tmp/dir1 \
 && cp /opt/golden/test_arit.py /tmp/dir1/sympy/core/tests/test_arit.py \
 && ( cd /tmp/dir1 && PYTHONPATH=/tmp/dir1 python3 -m pytest 'sympy/core/tests/test_arit.py::test_Mod' -p no:cacheprovider > /tmp/dir1.log 2>&1; echo "dir1 rc=$?" ) \
 && grep -qE 'FAILED.*test_Mod' /tmp/dir1.log && grep -qE '[1-9]+ failed' /tmp/dir1.log \
 && echo "DIRECTION 1 OK: golden test FAILS on the parent tree" \
 && cp -a /app/src /tmp/dir2 \
 && git show ${UPSTREAM_SHA_FIX}:sympy/core/mod.py > /tmp/dir2/sympy/core/mod.py \
 && cp /opt/golden/test_arit.py /tmp/dir2/sympy/core/tests/test_arit.py \
 && ( cd /tmp/dir2 && PYTHONPATH=/tmp/dir2 python3 -m pytest 'sympy/core/tests/test_arit.py::test_Mod' -p no:cacheprovider > /tmp/dir2.log 2>&1; echo "dir2 rc=$?" ) \
 && grep -qE '1 passed' /tmp/dir2.log \
 && echo "DIRECTION 2 OK: golden test PASSES on the fixed tree" \
 && cd / \
 && rm -rf /tmp/fixclone /tmp/dir1 /tmp/dir2 /tmp/dir1.log /tmp/dir2.log

# ---- belt: prove the fix commit is not reachable from the trial clone ------
# The object store of /app/src holds exactly one commit (the parent, fetched
# by SHA with --depth 1); the fix commit and every blob it introduced were
# never fetched there. The verifier re-asserts this at trial time.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# ---- sha256 pins of the two trusted files, for the verifier ----------------
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_arit.py | awk '{print $1 "  /opt/golden/test_arit.py"}' > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/mod.py | awk '{print $1 "  /opt/prefix/mod.py"}' > /opt/pins/prefix-mod.sha256 \
 && cat /opt/pins/golden.sha256 /opt/pins/prefix-mod.sha256

# Single CPU: keep numeric libraries single-threaded (spec requirement).
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]