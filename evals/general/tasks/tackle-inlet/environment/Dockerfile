# tackle-inlet: NLTK's Hungarian Snowball stemmer crashes on the empty string
# (upstream issue #3785, fixed upstream by commit 5c4c0d3fe... immediately
# after the pinned parent 47e236e95...).
#
# The image clones nltk/nltk SHALLOW and detached at the PARENT commit, so
# the working tree at /app/src carries the real, still-present bug. The
# project is installed EDITABLE from that tree (`pip install -e .`), so
# `import nltk` resolves into the clone and an agent's source edit is live
# without any reinstall step.
#
# The project's own regression test for this bug (nltk/test/unit/
# test_snowball.py -- a NEW file in the fix commit) is extracted from the fix
# commit into /opt/golden at build time through a THROWAWAY clone under /tmp
# that is deleted immediately, so the fix commit never exists inside
# /app/src/.git -- verified with `! git cat-file -e` both right after the
# working-clone fetch and again after the throwaway clone is removed.
#
# Both directions are re-confirmed INSIDE this image as cached layers:
#   parent: SnowballStemmer('hungarian').stem('') raises IndexError and the
#           golden test fails exactly the 'hungarian' subtest (1 failed,
#           1 passed, 15 subtests passed);
#   fix:    with the upstream-shaped guard applied (in-process via an
#           importlib override, so /app/src never leaves its pristine state),
#           stem('') == '' and the full golden test is green.
#
# cpus = 1 in task.toml: the numeric thread pools are pinned below. The
# trial has no guaranteed network: every dependency is baked into this image
# and nltk's stemmers need no corpus data.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=47e236e9505c6f552d6712a21c6d960879ba7f1e
ARG FIX_SHA=5c4c0d3fe65912fce05dae78dc76553b9e2bec85

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: the buggy PARENT commit, nothing else -------------------
# git init + one depth-1 fetch of the pinned SHA: the object store in
# /app/src contains ONLY the parent commit object. Tag/sha-pin assertion
# makes the build fail closed if upstream ever moves.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git rev-list --all --count)" = "1" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test -z "$(git status --porcelain)" \
 && echo "tackle-inlet: clone pinned at parent, fix commit unreachable"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone under /tmp, deleted immediately: the fix commit never
# enters /app/src/.git and the upstream test bytes live only in the image.
RUN git init -q /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:nltk/test/unit/test_snowball.py > /opt/golden/test_snowball.py \
 && test -s /opt/golden/test_snowball.py \
 && test "$(sha256sum /opt/golden/test_snowball.py | cut -d' ' -f1)" = "384f871f47156d369a13464e0184be9f9f095be95c5370120b18b7ef21c67eb4" \
 && grep -q "def test_empty_string_handling" /opt/golden/test_snowball.py \
 && grep -q "SnowballStemmer.languages" /opt/golden/test_snowball.py \
 && chmod a+r /opt/golden/test_snowball.py \
 && cd / && rm -rf /tmp/fixsrc \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && echo "tackle-inlet: golden test extracted, fix commit still unreachable"

# ---- install the project (editable, from the buggy tree) + test deps -------
# Exact pins for py3.12.13, resolved on this base image.
RUN cd /app/src \
 && pip install --no-cache-dir --disable-pip-version-check -e . \
 && pip install --no-cache-dir --disable-pip-version-check \
      numpy==2.5.3 pytest==9.1.1 pytest-mock==3.15.1 regex==2026.9.10 \
      pyyaml==6.0.3 click==8.5.0 tqdm==4.70.1 joblib==1.6.0 defusedxml==0.7.1 \
 && python3 -c "import nltk; print('nltk imports, version', nltk.__version__)" \
 && test -z "$(git -C /app/src status --porcelain)" \
 && echo "tackle-inlet: editable install done, tree still pristine"

# ---- build-time direction 1 (PARENT): symptom + golden test fail ------------
RUN python3 - <<'EOF'
from nltk.stem.snowball import SnowballStemmer
try:
    r = SnowballStemmer("hungarian").stem("")
except IndexError as e:
    print("direction-parent: IndexError reproduced:", e)
else:
    raise SystemExit("BUG-ABSENT: hungarian stem('') returned %r at parent" % r)
EOF
RUN cd /tmp && { python3 -m pytest -q -p no:cacheprovider /opt/golden/test_snowball.py \
      > /tmp/golden-parent.log 2>&1; rc=$?; } || true; \
    if [ "$rc" -eq 0 ]; then \
      echo "golden test unexpectedly passed at parent"; tail -20 /tmp/golden-parent.log; exit 1; \
    fi; \
    grep -q "1 failed" /tmp/golden-parent.log || { echo "golden-parent: expected 1 failed"; tail -20 /tmp/golden-parent.log; exit 1; } ; \
    grep -q "hungarian" /tmp/golden-parent.log || { echo "golden-parent: hungarian not the failing language"; tail -20 /tmp/golden-parent.log; exit 1; } ; \
    echo "direction-parent: golden test fails exactly on hungarian"

# ---- build-time direction 2 (FIX): the upstream-shaped guard turns both -----
# green. Applied IN-PROCESS (importlib override) so /app/src ships pristine.
RUN cd /tmp && python3 - <<'EOF'
import sys, types

src = open("/app/src/nltk/stem/snowball.py").read()
i = src.index("class HungarianStemmer")
j = src.index("if word in self.stopwords:", i)
k = src.rindex("word = word.lower()", i, j)
assert src[k:k+55] == "word = word.lower()\n\n        if word in self.stopwords:", "unexpected context for the guard site"
src = src[:k] + "word = word.lower()\n\n        if not word:\n            return word" + src[k+19:]

mod = types.ModuleType("nltk.stem.snowball")
exec(compile(src, "/app/src/nltk/stem/snowball.py", "exec"), mod.__dict__)
sys.modules["nltk.stem.snowball"] = mod
from nltk.stem.snowball import SnowballStemmer
assert SnowballStemmer("hungarian").stem("") == ""
assert SnowballStemmer("hungarian").stem("sarki") == "sar"
print("direction-fix: stem('') == '', stem('sarki') == 'sar'")

import pytest
rc = pytest.main(["-q", "-p", "no:cacheprovider", "/opt/golden/test_snowball.py"])
sys.exit(0 if rc == 0 else 1)
EOF

# ---- make the tree and /app writable for whichever uid the trial uses -------
RUN chmod -R a+rwX /app/src && chmod -R a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]