# galiot-cinder: falconry/falcon — falcon.testing.create_environ() reports
# RAW_URI as '/' regardless of the requested path (upstream issue #2157; the
# upstream fix commit 69cdcd6edd2ee33f4ac9f7793e1cc3c4f99da692 renames the
# path to raw_path before percent-decoding and uses it for RAW_URI).
#
# The image ships a git checkout of falcon whose object store holds exactly
# ONE commit: the PARENT commit 7191be4d19592401f38a7b8e824e9669d34dad2b (the
# real upstream bug is present in the working tree). The fix commit is never
# fetched into the working clone, so the answer is not reachable from the tree
# the agent works on; the regression test the fix commit added is extracted
# through a SEPARATE throwaway bare clone under /tmp that is deleted again,
# and is stored at /opt/golden/ where the agent is told not to look. Fail
# closed if the pin ever moves.
#
# The project is installed editable (`pip install -e .`) with exact pins, so
# `python3 /app/reproduce_bug.py` and `python3 -m pytest` work offline in the
# trial. A build-time smoke (environment/files/check_parent.py) proves the
# shipped tree still exhibits the mined defect (RAW_URI == '/'), and a second
# smoke proves the extracted regression test fails on the shipped tree (it
# must fail on the buggy tree and pass only after a fix).
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=7191be4d19592401f38a7b8e824e9669d34dad2b
ARG FIX_SHA=69cdcd6edd2ee33f4ac9f7793e1cc3c4f99da692

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# ---- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- working checkout: buggy parent commit, fix commit unreachable ------------
# Fetch exactly the parent commit (shallow). GitHub permits fetching an
# arbitrary reachable commit SHA, so the working clone's object store ends up
# containing exactly one commit; the fix commit is not in it and cannot become
# reachable without network.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin $UPSTREAM_SHA \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# Owned build-time helpers (check_parent.py smoke; extract_golden.py). Both are
# deleted by the build before the trial, so /app is left empty for the agent's
# /app/reproduce_bug.py deliverable.
COPY files/ /app/

# ---- extract the upstream regression test from the FIX commit -----------------
# Throwaway bare clone; the fix object never enters /app/src/.git. The file is
# the verbatim test_create_environ_preserve_raw_uri function with a small
# header; extract_golden.py asserts the sha256 the verifier later checks, so
# the image fails closed if the extraction drifts. The extractor script is
# deleted after use.
RUN mkdir -p /opt/golden \
 && git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin $FIX_SHA \
 && git show $FIX_SHA:tests/test_testing.py > /tmp/tt_testing.py \
 && python3 /app/extract_golden.py \
 && cd / && rm -rf /tmp/fixsrc /tmp/tt_testing.py /app/extract_golden.py

# ---- install (warm every cache at build time; the trial is offline) -----------
RUN cd /app/src \
 && pip install --no-cache-dir cython==3.1.6 setuptools==75.8.0 wheel==0.45.1 pytest==8.4.1 \
 && pip install --no-cache-dir --no-build-isolation -e .

# ---- build-time smoke: no stray files, bug still present, golden fails -------
# 1. the editable install must leave the checkout clean (gitignore covers
#    *.so, *.egg-info, build; or the porcelain gate would fail);
# 2. the shipped tree must still exhibit the mined defect (RAW_URI == '/');
# 3. the extracted regression test must FAIL on the buggy tree (fail closed:
#    an image where the golden test passes on the parent is not the mined
#    state and must not ship).
RUN test -z "$(git -C /app/src status --porcelain)"

RUN cd /app/src && python3 /app/check_parent.py && rm /app/check_parent.py

RUN cd /app/src \
 && (python3 -m pytest /opt/golden/test_preserve_raw_uri.py -q -p no:cacheprovider \
       > /tmp/golden-parent.log 2>&1; rc=$?; test "$rc" -ne 0) \
 && grep -q "1 failed" /tmp/golden-parent.log \
 && rm -f /tmp/golden-parent.log

# ---- open the trees for whichever uid the trial uses --------------------------
RUN chmod -R a+rwX /app /app/src /opt/golden

WORKDIR /app

CMD ["/bin/bash"]