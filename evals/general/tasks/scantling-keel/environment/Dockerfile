ARG UPSTREAM_SHA_PARENT=08e73e6bd6a5227e9382ea313715b363c06e88ad
ARG UPSTREAM_SHA_FIX=d696c93fbb25f062f963b58a98c0ac1a07fec3fc

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Global git config so the trial (uid 1000 or root) can use the clones.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- trial clone: the REAL upstream sympy repository at exactly the parent
# --- commit, shallow (single depth-1 fetch). The fix commit is NEVER
# --- fetched into this clone. Ownership is set in the same RUN that
# --- materialises the tree so the tree bytes are stored once.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "trial clone at parent pin: $(git rev-parse HEAD)" \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src

# Fail closed if the fix commit is reachable from the trial clone. The object
# store was produced by a single depth-1 fetch of the parent, so only the
# parent commit and its blobs exist.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit ${UPSTREAM_SHA_FIX} reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from the trial clone; HEAD = $(git rev-parse HEAD)"

# --- install: editable sympy from the trial tree (edits to /app/src are
# --- live), plus the runtime/test dependencies pinned by the mining run.
# --- Ownership of the tree is re-applied in this same RUN.
RUN pip install --no-cache-dir -e /app/src \
 && pip install --no-cache-dir mpmath==1.3.0 pytest==9.1.1 hypothesis==6.168.0 \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src \
 && cd /app/src \
 && python -c "import sympy, mpmath; print('sympy', sympy.__version__, '| mpmath', mpmath.__version__, '| imported from', sympy.__file__)"

# --- pristine PRE-FIX reference tree at /opt/prefix-sympy: a SECOND shallow
# --- checkout of the same parent commit, never modified. The verifier runs
# --- the agent's reproduction and the golden test against it to prove the
# --- symptom is real, and diffs the whole working tree against it for the
# --- scope check.
RUN git init -q /opt/prefix-sympy \
 && cd /opt/prefix-sympy \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "pre-fix reference tree at parent pin: $(git rev-parse HEAD)" \
 && chown -R 1000:1000 /opt/prefix-sympy \
 && chmod -R a+rwX /opt/prefix-sympy

# --- parent-direction confirmation IN THIS IMAGE: both the editable install
# --- of the trial clone and the pre-fix reference tree must reproduce the
# --- raw TypeError crash on the two-equation mixed sign systems, and the
# --- lone sign equation must return the condition-set-wrapped placeholder.
RUN cat > /tmp/reprocheck.py <<'PY'
import os, sys
src = os.environ.get('SYMPY_SRC')
if src:
    sys.path.insert(1, os.path.abspath(src))
import sympy
print('reprocheck importing sympy from', sympy.__file__)
from sympy import nonlinsolve, sign, symbols
x, y = symbols('x y')
crashes = 0
for label, system in (("A", [sign(x) - 1, x*y - 4]), ("B", [sign(x) - 1, x - y])):
    try:
        nonlinsolve(system, [x, y])
        print(label, "DID NOT CRASH - bug not present at this commit")
        raise SystemExit(1)
    except TypeError:
        crashes += 1
        print(label, "crash reproduced: TypeError")
    except Exception as exc:
        print(label, "unexpected exception", type(exc).__name__, str(exc)[:80])
        raise SystemExit(1)
r = nonlinsolve([sign(x) - 1], [x])
print("single:", type(r).__name__, r)
assert crashes == 2, "both two-equation systems must crash at the parent"
print("parent direction confirmed: raw TypeError crash reproduces in this image")
PY
RUN cd /app/src && SYMPY_SRC=/opt/prefix-sympy python3 /tmp/reprocheck.py \
 && cd /app/src && python3 /tmp/reprocheck.py \
 && rm -f /tmp/reprocheck.py

# --- golden test: the project's own regression test for this bug, extracted
# --- from the FIX commit through a SEPARATE throwaway clone that is deleted
# --- immediately afterwards, so the fix object never enters /app/src and no
# --- upstream test bytes enter this task tree. The full test file is kept
# --- because pytest selects the node from the real module.
# --- Trust anchors: sha256 pins of the golden file, of the pre-fix solver
# --- file, and of the interpreter / pip / pytest executables.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden /opt/pins \
 && git show ${UPSTREAM_SHA_FIX}:sympy/solvers/tests/test_solveset.py \
      > /opt/golden/test_solveset.py \
 && test -s /opt/golden/test_solveset.py \
 && grep -q "def test_nonlinsolve_sign" /opt/golden/test_solveset.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && sha256sum /opt/golden/test_solveset.py > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix-sympy/sympy/solvers/solveset.py \
      > /opt/pins/prefix-solveset.sha256 \
 && sha256sum /usr/local/bin/python3.12 /usr/local/bin/pip \
      /usr/local/bin/pytest > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/golden /opt/pins \
 && chmod 444 /opt/golden/test_solveset.py /opt/pins/*.sha256 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-solveset.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden test, pre-fix solver and toolchain pinned"

# --- belt: the golden test must FAIL against the pristine pre-fix tree when
# --- mounted in a THROWAWAY COPY of it (the copy is deleted afterwards, so
# --- /opt/prefix-sympy itself stays byte-identical to the parent commit and
# --- remains usable as the verifier's scope-diff reference). This proves the
# --- golden test discriminates inside this image and let the mining
# --- reproduction be re-confirmed here under the shipped dependency pins.
RUN cp -a /opt/prefix-sympy /tmp/prefix-golden \
 && cp /opt/golden/test_solveset.py /tmp/prefix-golden/sympy/solvers/tests/test_solveset.py \
 && cd /tmp/prefix-golden \
 && chmod -R a+rwX /tmp/prefix-golden \
 && SYMPY_SRC=/tmp/prefix-golden python3 -m pytest \
      'sympy/solvers/tests/test_solveset.py::test_nonlinsolve_sign' \
      -p no:cacheprovider > /tmp/golden-prefix.out 2>&1; rc=$?; \
    echo "golden vs pre-fix tree rc=$rc"; tail -3 /tmp/golden-prefix.out; \
    if [ "$rc" -eq 0 ]; then echo "ERROR: golden test passed on the pre-fix tree"; exit 1; fi; \
    grep -q "TypeError" /tmp/golden-prefix.out || { echo "no TypeError seen"; exit 1; }; \
    cd / && rm -rf /tmp/prefix-golden; \
    echo "golden discriminates: fails on the pre-fix tree with TypeError"

# Final tidy-up of build-time scratch.
RUN rm -rf /tmp/golden-prefix.out /root/.cache/pip

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app
CMD ["/bin/bash"]