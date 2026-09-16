# capstan-overtake: explosion/spaCy — displaCy render(..., jupyter=True) crashes
# with ImportError on IPython>=9 (upstream issue #13876; the upstream fix
# commit 94d6be8a9b1dbecc92820bd7996cd8c75e186320 contains NO regression test,
# so the golden test here is authored from the reproduction).
#
# The image creates a git checkout of explosion/spaCy whose object store holds
# exactly ONE commit: the PARENT commit f5d04868e1e66d0acd6417b1c8099bcd4068fff7
# (the real upstream bug is present in the working tree). The fix commit is
# never fetched, so the answer is not reachable from the tree the agent works
# on. Fail closed if the pin ever moves.
#
# `pip install -e .` compiles spaCy's Cython extensions in place and installs
# everything the trial needs (warm cache; the trial is offline). ipython is
# pinned to 9.17.1 because the bug only manifests on IPython>=9. pytest and
# hypothesis are the editorially minimal test dependencies the project's own
# tests/conftest.py requires in order to run the existing displaCy test module.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=f5d04868e1e66d0acd6417b1c8099bcd4068fff7
ARG FIX_SHA=94d6be8a9b1dbecc92820bd7996cd8c75e186320

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

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
 && git remote add origin https://github.com/explosion/spaCy.git \
 && git fetch --depth 1 origin f5d04868e1e66d0acd6417b1c8099bcd4068fff7 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- install (warm every cache at build time; the trial is offline) -----------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN cd /app/src \
 && pip install -e . \
 && pip install --no-cache-dir pytest==9.1.1 hypothesis==6.168.0 ipython==9.17.1 click==8.5.0

WORKDIR /app

COPY files/ /app/

# Keep the authored golden regression test out of the agent's tree (the
# verifier reads it from /opt/golden at trial time).
RUN mkdir -p /opt/golden \
 && mv /app/golden/test_displacy_jupyter.py /opt/golden/test_displacy_jupyter.py \
 && rm -rf /app/golden \
 && test -s /opt/golden/test_displacy_jupyter.py

# ---- build-time smoke: the parent must reproduce the mined failure ------------
RUN cd /app/src && python3 /app/check_parent.py && rm /app/check_parent.py

# ---- the project's own existing displaCy suite passes at the parent -----------
# (the bug only affects the jupyter=True path, which the existing suite never
# exercises, so all of its tests are green on the untouched checkout)
RUN cd /app/src && python3 -m pytest spacy/tests/test_displacy.py -q -p no:cacheprovider > /tmp/suite-smoke.log 2>&1 \
 && tail -n 2 /tmp/suite-smoke.log

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]