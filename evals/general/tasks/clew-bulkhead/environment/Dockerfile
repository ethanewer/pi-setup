# clew-bulkhead: scipy/scipy upstream-clone debugging task.
# The image clones scipy at the PARENT commit (the bug present), warm-builds it
# EDITABLY (meson-python: sources in /app/src, compiled outputs in
# /work/sci-build), bakes a pristine PRE-FIX snapshot of the installed package
# at /opt/prefix-pylib (the verifier's fail-direction target), extracts the
# project's own regression test for the bug from the FIX commit via a
# THROWAWAY clone under /tmp (deleted immediately afterwards, so the fix
# object never enters /app/src), and pins hashes of the golden test, the
# pre-fix snapshot and the toolchain.
ARG UPSTREAM_SHA_PARENT=4fe05c739b70795b595e1aee3bed87068463123f
ARG UPSTREAM_SHA_FIX=d42bc45c3ffecb0f76398b3f23eeba78a2dc13ac

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PKG_CONFIG_PATH=/opt/openblas-pc

# ---- toolchain: gcc/g++/gfortran + OpenBLAS, discovered via pkg-config ----
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc g++ gfortran pkg-config git \
      libopenblas0-pthread libblas3 liblapack3 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/openblas-pc \
 && printf 'prefix=/usr/lib/x86_64-linux-gnu\nexec_prefix=${prefix}\nlibdir=${prefix}\nincludedir=/usr/include\n\nName: OpenBLAS\nDescription: OpenBLAS (pthread), shim for scipy build\nVersion: 0.3.29\nLibs: -L${libdir} -lopenblas\nCflags: -I${includedir}\n' > /opt/openblas-pc/openblas.pc \
 && ln -sf /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so.0 /usr/lib/x86_64-linux-gnu/libopenblas.so \
 && echo /usr/lib/x86_64-linux-gnu > /etc/ld.so.conf.d/openblas.conf \
 && ldconfig \
 && test -f /usr/lib/x86_64-linux-gnu/libopenblas.so \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- python build/test deps, exact pins ----
RUN pip install --no-cache-dir \
      numpy==2.5.3 cython==3.3.0 meson==1.12.0 meson-python==0.21.1 \
      ninja==1.13.2 pybind11==3.1.0 pythran==0.19.0 \
      pytest==9.1.1 hypothesis==6.168.0 pooch==1.9.0 \
      pytest-xdist==3.8.0 pytest-timeout==2.4.0 mpmath==1.4.1

# ---- clone scipy at the PARENT commit (shallow, pinned, fail closed); the
#      fix commit is never fetched into this clone ----
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/scipy/scipy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && git submodule update --init --depth 1

# ---- warm EDITABLE build at the parent commit. One RUN so the chown lands in
#      the same layer as the files it fixes (no copy-on-write duplication).
#      From here on pip is locked offline (PIP_NO_INDEX=1), proving the
#      installs need no network. ----
ENV PIP_NO_INDEX=1 PIP_CONFIG_FILE=/dev/null
RUN cd /app/src \
 && python3 -m pip install -e . --no-build-isolation \
      --config-settings=builddir=/work/sci-build > /tmp/build.log 2>&1; rc=$?; \
    test $rc -eq 0 || { echo "WARM BUILD FAILED rc=$rc"; tail -60 /tmp/build.log; exit 1; } \
 && cd /tmp && python3 -c "import scipy; print('warm import ok', scipy.__version__)" \
 && cd /app/src \
 && n=0; while IFS= read -r -d '' f; do \
      want=$(git rev-parse "HEAD:$f" 2>/dev/null || true); \
      [ -n "$want" ] || continue; \
      case "$(git ls-files -s -- "$f" | awk '{print $1}')" in \
        160000*) : ;; \
        120000*) have=$(readlink "$f" 2>/dev/null || true); \
                 want2=$(git cat-file blob "$want" 2>/dev/null || true); \
                 [ "$have" = "$want2" ] || { echo "UNEXPECTED DIFF: $f"; n=$((n+1)); };; \
        *) git cat-file blob "$want" 2>/dev/null | cmp -s - "$f" \
             || { echo "UNEXPECTED DIFF: $f"; n=$((n+1)); };; \
      esac; \
    done < <(git ls-files -z); \
    test "$n" -eq 0 || { echo "$n files differ from parent blobs after the warm install"; exit 1; } \
 && echo "warm editable build ok, tree byte-identical to parent" \
 && chown -R 1000:1000 /app/src /work \
 && chmod -R a+rwX /app/src /work

# ---- parent-direction confirmation in THIS image: the direct repro must
#      raise the internal IndexError (never a clean ValueError) ----
RUN cd /tmp && python3 - <<'EOF'
import numpy as np
from scipy.spatial import ConvexHull
try:
    ConvexHull(np.ones((5,)))
except IndexError:
    print("parent-direction OK: IndexError raised (bug present)")
except BaseException as e:
    print("UNEXPECTED:", type(e).__name__, e); raise SystemExit(1)
else:
    print("UNEXPECTED: no error"); raise SystemExit(1)
EOF

# ---- bake a pristine PRE-FIX snapshot of the installed package: stage the
#      project's own install output (meson install) into /opt/prefix-pylib so
#      the snapshot has the TRUE installed layout (generated __config__,
#      vendored subpackages, every compiled module). The verifier imports
#      scipy from here (with the editable finder disabled) to run the agent's
#      reproduction against the pre-fix tree and require it to FAIL. ----
RUN meson install -C /work/sci-build --destdir /opt/prefix-pylib \
      > /tmp/prefix-install.log 2>&1; rc=$?; \
    test $rc -eq 0 || { echo "PREFIX SNAPSHOT INSTALL FAILED rc=$rc"; tail -20 /tmp/prefix-install.log; exit 1; } \
 && ls /opt/prefix-pylib/usr/local/lib/python3.12/site-packages/scipy/spatial/_qhull.cpython-312-x86_64-linux-gnu.so \
 && cd /tmp \
 && MESONPY_EDITABLE_SKIP=/work/sci-build \
      PYTHONPATH=/opt/prefix-pylib/usr/local/lib/python3.12/site-packages python3 - <<'EOF'
import numpy as np
from scipy.spatial import ConvexHull
try:
    ConvexHull(np.ones((5,)))
except IndexError:
    print("prefix snapshot OK: pre-fix IndexError visible through snapshot")
except BaseException as e:
    print("UNEXPECTED:", type(e).__name__, e); raise SystemExit(1)
else:
    print("UNEXPECTED: no error"); raise SystemExit(1)
EOF

# ---- extract the project's own regression test for this bug from the FIX
#      commit, through a THROWAWAY clone that is deleted immediately, so the
#      fix object never enters /app/src ----
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/scipy/scipy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:scipy/spatial/tests/test_qhull.py \
      > /opt/golden/test_qhull.py \
 && test -s /opt/golden/test_qhull.py \
 && grep -q "def test_points_wrong_dim_fails" /opt/golden/test_qhull.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && test -z "$(ls -A /tmp/upstream-fix-clone 2>/dev/null || true)"

# ---- belt: the fix commit must not be reachable from /app/src; HEAD must
#      still be the pinned parent; and the tree must be byte-clean (content
#      check, immune to git's stat cache). ----
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && n=0; while IFS= read -r -d '' f; do \
      want=$(git rev-parse "HEAD:$f" 2>/dev/null || true); \
      [ -n "$want" ] || continue; \
      case "$(git ls-files -s -- "$f" | awk '{print $1}')" in \
        160000*) : ;; \
        120000*) have=$(readlink "$f" 2>/dev/null || true); \
                 want2=$(git cat-file blob "$want" 2>/dev/null || true); \
                 [ "$have" = "$want2" ] || { echo "UNEXPECTED DIFF: $f"; n=$((n+1)); };; \
        *) git cat-file blob "$want" 2>/dev/null | cmp -s - "$f" \
             || { echo "UNEXPECTED DIFF: $f"; n=$((n+1)); };; \
      esac; \
    done < <(git ls-files -z); \
    test "$n" -eq 0 || { echo "$n files differ from parent blobs"; exit 1; } \
 && echo "fix commit unreachable from /app/src; HEAD=$(git rev-parse HEAD); tree byte-clean"

# ---- integrity pins: golden regression test, pre-fix snapshot, toolchain ----
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_qhull.py > /opt/pins/golden.sha256 \
 && find /opt/prefix-pylib -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
      > /opt/pins/prefix.sha256 \
 && test "$(wc -l < /opt/pins/prefix.sha256)" -ge 400 \
 && sha256sum /usr/bin/gcc /usr/bin/g++ /usr/bin/ld /usr/bin/gfortran \
              /usr/local/bin/python3 /usr/local/bin/ninja \
              /usr/local/lib/python3.12/site-packages/_scipy_editable_loader.py \
              /usr/local/lib/python3.12/site-packages/scipy-editable.pth \
      > /opt/pins/toolchain.sha256 \
 && chmod -R a+rX /opt/golden /opt/prefix-pylib /opt/pins \
 && chmod 555 /opt/golden /opt/prefix-pylib /opt/pins \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix snapshot + toolchain pinned"

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/*.md 2>/dev/null || true

WORKDIR /app
CMD ["/bin/bash"]