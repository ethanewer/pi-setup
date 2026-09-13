# ballast-pilot: RIBES machine-translation scoring crashes on empty inputs.
#
# The image clones nltk/nltk SHALLOW at the PARENT commit (the real upstream
# bug, issue #3604, is present in the working tree) and installs it in editable
# mode, so the code the agent imports is exactly the checked-out Python source
# and its edits take effect immediately. The project's own regression tests for
# the bug are extracted from the FIX commit at build time into /opt/golden/
# (upstream bytes never enter this repository). The fix commit is a descendant
# of the parent, so it is NOT reachable from the depth-1 working clone; the
# extraction uses a throwaway bare clone that is deleted afterwards.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=a167389c027a02a9d1f019630ed827f4069b3353
ARG FIX_SHA=06c0e2cc94f763d43320812ee9d2a7b6bff68f9b

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of the default branch cannot contain the parent SHA, so fetch
# the parent by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/nltk/nltk.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin a167389c027a02a9d1f019630ed827f4069b3353 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin 06c0e2cc94f763d43320812ee9d2a7b6bff68f9b \
 && mkdir -p /opt/golden \
 && git show 06c0e2cc94f763d43320812ee9d2a7b6bff68f9b:nltk/test/unit/test_ribes.py \
      > /opt/golden/test_ribes.py \
 && test -s /opt/golden/test_ribes.py \
 && grep -q "def test_ribes_empty_hypothesis" /opt/golden/test_ribes.py \
 && grep -q "def test_ribes_rejects_mismatched_corpus_lengths" /opt/golden/test_ribes.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN cd /app/src \
 && python3 -m pip install -e . \
 && python3 -m pip install numpy==2.3.5 pytest==8.4.2 pytest-mock==3.15.1 \
            regex==2024.11.6 pyyaml==6.0.2 click==8.1.8 tqdm==4.67.1 \
            joblib==1.4.2 defusedxml==0.7.1

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]