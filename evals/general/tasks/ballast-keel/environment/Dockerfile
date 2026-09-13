# ---------------------------------------------------------------------------
# ballast-keel: librosa's note_to_hz silently discards cents tuning
# deviations (upstream issue #1945).
#
# The image clones librosa/librosa and checks out upstream PARENT commit
# a0d0374370183d93ad7a4a348da034ab5b3e1687 (immediately before upstream commit
# 86d728a4fae31c5e80ef112f895c70af228d1637 fixed issue #1945), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test is extracted
# from the fix commit in a throwaway clone that is deleted, so the fix bytes
# never land in the working clone either.
#
# The project is installed in editable mode (`pip install -e .`), so the
# agent's edits to files under /app/src/librosa are live without any
# reinstall step. librosa is a pure-Python / numba package: no compilation
# happens at trial time; a single `python3 -m pytest tests/...` is the whole
# fix-verify cycle.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=a0d0374370183d93ad7a4a348da034ab5b3e1687
ARG FIX_SHA=86d728a4fae31c5e80ef112f895c70af228d1637

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/librosa/librosa.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the upstream test bytes live only in the image at
# /opt/golden/ (never in this repository's tree).
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/librosa/librosa.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:tests/test_convert.py \
      > /opt/golden/test_convert.py \
 && test -s /opt/golden/test_convert.py \
 && test "$(sha256sum /opt/golden/test_convert.py | cut -d' ' -f1)" \
      = "3b5b30a5adb54fb8ed39a86073d7ec906e0f8071497dd5db576591ceac5beb97" \
 && grep -q "def test_note_to_hz_default" /opt/golden/test_convert.py \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_convert.py

# ---- runtime and test environment, fully pinned (the trial has no network) --
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# setuptools 72 is era-appropriate for this setup.cfg-only project (newer
# setuptools dropped [options]/[metadata] from setup.cfg); wheel is needed by
# the legacy editable install. numpy/scipy/numba are pinned to the exact
# versions the reproduction was verified against.
RUN pip install setuptools==72.0.0 wheel==0.44.0 \
                 numpy==2.5.3 scipy==1.18.1 numba==0.67.0 \
 && cd /app/src \
 && pip install -e '.[tests]' --no-build-isolation

# ---- build-time confirmation that the image ships the mined failing state ----
# Smoke in a throwaway copy so /app/src stays pristine at the parent commit:
#  1) the issue symptom reproduces: note_to_hz('C2-30') equals note_to_hz('C2')
#     (the -30 cent deviation is silently discarded);
#  2) the upstream regression test extracted from the fix commit FAILS
#     against the parent tree, exactly as mined. Pytest runs through a
#     wrapping python one-liner that pre-imports librosa.core.convert in the
#     same process: under lazy_loader>=0.4, pytest collection of the tree's
#     own tests otherwise dies with 'No librosa.core attribute convert'.
RUN cp -r /app/src /tmp/smoke \
 && python3 -c "import librosa; h = librosa.note_to_hz('C2-30'); print('note_to_hz(C2-30) =', repr(h), ' note_to_hz(C2) =', repr(librosa.note_to_hz('C2'))); assert h == librosa.note_to_hz('C2'), 'bug not present: deviation preserved at parent'; assert float(h) == 65.40639132514966" \
 && cp /opt/golden/test_convert.py /tmp/smoke/tests/test_convert.py \
 && cd /tmp/smoke \
 && { python3 -c "import sys, librosa.core.convert, pytest; sys.exit(pytest.main(list(sys.argv[1:])))" "tests/test_convert.py::test_note_to_hz_default" -o addopts= -p no:cacheprovider -q > /tmp/smoke-golden.log 2>&1; rc=$?; } \
 && [ "$rc" -ne 0 ] \
 && grep -q "1 failed" /tmp/smoke-golden.log \
 && tail -2 /tmp/smoke-golden.log \
 && rm -rf /tmp/smoke

WORKDIR /app

CMD ["/bin/bash"]