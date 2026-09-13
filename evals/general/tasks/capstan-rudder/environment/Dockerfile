# capstan-rudder: librosa/librosa note-conversion functions crash on
# non-finite pitch values (upstream issue #1944).
#
# The image clones librosa/librosa SHALLOW at the PARENT commit 86d728a4...
# (the real upstream bug is present in the working tree), extracts the
# project's own regression tests for the bug from the FIX commit at build
# time into /opt/golden/test_convert_fix.py, and ships an authored
# conftest.py there so pytest collection survives lazy_loader >= 0.4 (the
# conversion module is pre-imported ahead of the test module, exactly as
# the mining pass did). The fix commit is fetched only into a throwaway
# bare clone that is deleted afterwards, so it is never reachable from
# /app/src. librosa is not a Terminal-Bench 2.1 source repository (checked
# against specs/tb21_source_repositories.json). The library is pure Python
# and is imported straight from /app/src via PYTHONPATH, so the agent's
# edit-to-test cycle has no build step at all.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONPATH=/app/src \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=86d728a4fae31c5e80ef112f895c70af228d1637
ARG FIX_SHA=025ef7d1c7ad6d8593b959c41bf12eb7c945c6eb

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- pinned runtime + test dependencies --------------------------------------
# Versions verified by the mining pass (numpy 2.5.3, scipy 1.18.1,
# numba 0.67.0, python 3.12.13). librosa/core/convert and its helpers need
# numpy and scipy (librosa._typing imports scipy.sparse), numba
# (notation.jit and the @vectorize entry points), msgpack (intervals),
# joblib (_cache), decorator, typing_extensions and pooch
# (librosa.util.files, imported by intervals); pytest runs the project's
# own suite.
RUN pip install --no-cache-dir \
        numpy==2.5.3 \
        scipy==1.18.1 \
        numba==0.67.0 \
        lazy_loader==0.5 \
        msgpack==1.2.2 \
        joblib==1.6.0 \
        decorator==5.3.1 \
        typing_extensions==4.16.0 \
        pooch==1.9.0 \
        pytest==9.1.1

# ---- working clone: buggy parent commit, fix commit unreachable --------------
# Fetch only the parent SHA with --depth 1, so 025ef7d1... and its
# descendants never enter /app/src/.git and cannot be fetched later (the
# trial has no network anyway).
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/librosa/librosa.git \
 && git fetch --depth 1 origin $UPSTREAM_SHA \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, deleted afterwards; the fix commit never exists
# inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/librosa/librosa.git \
 && git fetch --depth 1 origin $FIX_SHA \
 && mkdir -p /opt/golden \
 && git show $FIX_SHA:tests/test_convert.py > /opt/golden/test_convert_fix.py \
 && test "$(sha256sum /opt/golden/test_convert_fix.py | cut -d' ' -f1)" \
      = "1e667700400a090ff6e63d1ae196f89070abc1745c3581a58dd4a0192b566c99" \
 && cd / && rm -rf /tmp/fixsrc

# Authored conftest for the golden directory: pre-imports the conversion
# module ahead of pytest's collection of the test module (the lazy_loader
# >= 0.4 workaround the mining pass used).
RUN printf 'import librosa.core.convert  # noqa: F401\n' > /opt/golden/conftest.py

# ---- smoke: the parent bug reproduces inside the image -----------------------
RUN cd /tmp && python3 - <<'EOF'
import numpy as np
import librosa
import librosa.core.convert  # lazy_loader >= 0.4: load ahead of use

assert librosa.__file__.startswith("/app/src/"), librosa.__file__

for value in (np.nan, np.inf, -np.inf):
    try:
        librosa.midi_to_note(value)
    except (ValueError, OverflowError):
        continue
    raise SystemExit("midi_to_note(%r) did not raise at the parent commit" % value)

try:
    librosa.note_to_midi("")
except Exception:
    pass
else:
    raise SystemExit('note_to_midi("") did not raise at the parent commit')

print("ok: parent bug present (ValueError/OverflowError/ParameterError)")
EOF

# ---- build-time snapshots of the read-only environment ----------------------
# The verifier re-derives these manifests at trial time and fails the task
# if anything outside the deliverable /app/src was added, removed or
# modified -- e.g. a sitecustomize.py / .pth hook installed into
# site-packages, an edited stdlib module, a wrapper around pytest, or a
# tampered /opt/golden test file or conftest. Snapshot the whole python
# install tree (incl. site-packages), /usr/local/bin (python3, pytest, ...)
# and /opt/golden. __pycache__ is excluded: interpreter runs legitimately
# write bytecode there.
RUN mkdir -p /opt/manifests \
 && LC_ALL=C find /usr/local/lib/python3.12 \( -type f -o -type l \) ! -path '*/__pycache__/*' -print \
      | LC_ALL=C sort | xargs -r -d '\n' sha256sum > /opt/manifests/pylib.sha \
 && LC_ALL=C find /usr/local/bin \( -type f -o -type l \) -print \
      | LC_ALL=C sort | xargs -r -d '\n' sha256sum > /opt/manifests/bin.sha \
 && LC_ALL=C find /opt/golden \( -type f -o -type l \) ! -path '*/__pycache__/*' -print \
      | LC_ALL=C sort | xargs -r -d '\n' sha256sum > /opt/manifests/golden.sha \
 && chmod a+r /opt/manifests /opt/manifests/*.sha \
 && wc -l /opt/manifests/*.sha

WORKDIR /app

# The tree is pure Python and readable by every uid; the agent must edit it
# in place (numba also writes its cache into __pycache__).
RUN chmod -R a+rwX /app/src

CMD ["/bin/bash"]