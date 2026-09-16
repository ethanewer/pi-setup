# chainplate-boom: nltk chomsky_normal_form crashes on terminals with siblings
# (upstream fix 27b8ad6cd50a484590cb9409e5d2a891ab56e16c, closes #3693; the
# instruction.md names none of these).
#
# The image clones the REAL nltk/nltk SHALLOW at the PARENT commit
# (52227d2afe764648864e59c851e991cf1d6cb77e) and pip-installs it in editable
# mode, so the code the agent imports is exactly the checked-out Python
# source and its edits take effect immediately. The project's own regression
# tests for the bug (nltk/test/unit/test_treetransforms.py as of the fix
# commit) are extracted at build time into /opt/golden/: the two tests
# chomsky_normal_form must pass against a repaired tree, and the verifier
# runs them. The fix commit is a descendant of the parent, so it is NOT
# reachable from the depth-1 working clone; the extraction uses a throwaway
# bare clone that is deleted immediately afterwards.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=52227d2afe764648864e59c851e991cf1d6cb77e
ARG FIX_SHA=27b8ad6cd50a484590cb9409e5d2a891ab56e16c
ARG GOLDEN_SHA=d956b521a97ee3ff324a5be593a70f48c02b7efb82cedea1dc3bf7923e5bf57b

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 fetch of the exact parent SHA puts ONLY that commit and the blobs
# of its tree in the object store, so the fix commit -- the only way any
# pre-written answer could enter the clone -- is not present. Fail closed if
# upstream ever moves or the fix commit becomes reachable.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone; the file's sha256 is asserted so a moved commit fails
# closed. Upstream test bytes never land in this task tree.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:nltk/test/unit/test_treetransforms.py \
      > /opt/golden/test_treetransforms.py \
 && test "$(sha256sum /opt/golden/test_treetransforms.py | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && grep -q "def test_chomsky_normal_form_with_terminal_siblings" /opt/golden/test_treetransforms.py \
 && grep -q "def test_chomsky_normal_form_with_nonstring_terminal" /opt/golden/test_treetransforms.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; the trial is offline) --------
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
RUN chmod a+rx /app/probe_cnf.py /app/smoke.sh \
 && chmod a+rwX /app \
 && chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true

# ---- smoke: the image must ship the FAILING state (bug reproduces) ---------
RUN bash /app/smoke.sh && echo "SMOKE OK: chomsky_normal_form crashes on terminals with siblings at ${UPSTREAM_SHA}"

CMD ["/bin/bash"]