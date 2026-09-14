ARG UPSTREAM_SHA=a804efa6ece58f62f5b4af667eec70234c160276
ARG FIX_SHA=34d57a75ac3a7afa07266fb1e5b34cac19e9fd76

FROM bench-base:python-3.12

ARG UPSTREAM_SHA
ARG FIX_SHA

# ---------------------------------------------------------------------------
# Native toolchain for building scipy from source (Debian 13 trixie).
# apt versions are intentionally unpinned (Debian rotates its archives).
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ gfortran pkg-config libopenblas0-pthread libblas3 liblapack3 \
 && rm -rf /var/lib/apt/lists/*

# OpenBLAS from apt is discovered via pkg-config; provide the shim scipy's
# meson build expects, and point ldconfig at the pthread variant.
RUN mkdir -p /opt/openblas-pc \
 && printf 'prefix=/usr/lib/x86_64-linux-gnu/openblas-pthread\nlibdir=${prefix}\nincludedir=/usr/include\nName: openblas\nVersion: 0.3.29\nDescription: OpenBLAS\nLibs: -L${libdir} -lopenblas\nCflags: -I${includedir}\n' > /opt/openblas-pc/openblas.pc \
 && ln -sf /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so.0 /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so \
 && echo '/usr/lib/x86_64-linux-gnu/openblas-pthread' > /etc/ld.so.conf.d/openblas.conf \
 && ldconfig

# Python build/test dependencies, exact pins resolved against this base image.
RUN pip install --no-cache-dir \
        numpy==2.5.3 cython==3.3.0 meson==1.12.0 meson-python==0.21.1 \
        ninja==1.13.2 pybind11==3.1.0 pythran==0.19.0 pytest==9.1.1 \
        hypothesis==6.168.0 pooch==1.9.0 pytest-xdist==3.8.0 \
        pytest-timeout==2.4.0 mpmath==1.4.1

# ---------------------------------------------------------------------------
# The real upstream tree, pinned by 40-hex commit. Shallow single-commit
# checkout of the PARENT commit (the buggy revision) with no other history:
# `git log --all` shows exactly one commit, and the fix object never enters
# this clone. Fail closed if upstream ever moves the commit.
# ---------------------------------------------------------------------------
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/scipy/scipy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && chmod -R a+rwX /app/src
RUN cd /app/src && git submodule update --init --depth 1

# Single-threaded numeric libraries: trials run with cpus = 1.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# The expensive step, done once as a cached image layer: build scipy from
# source and install it in editable/dev mode so that importing 'scipy' maps
# straight into /app/src and pure-Python source edits take effect without a
# rebuild. /work/sci-build keeps the compiled extension modules.
RUN cd /app/src \
 && PKG_CONFIG_PATH=/opt/openblas-pc python -m pip install \
        --no-build-isolation \
        --config-settings=builddir=/work/sci-build \
        -e . \
 && chmod -R a+rwX /app/src /work

# ---------------------------------------------------------------------------
# Integrity assertions, re-checked after the build:
#   * HEAD is still the pinned buggy parent;
#   * the FIX commit is NOT reachable in the clone the agent will receive
#     (a shallow clone of one SHA cannot contain it; assert it anyway so the
#     build fails closed if this recipe ever changes);
#   * the origin remote is removed so nothing in the tree can be (re)fetched;
# ---------------------------------------------------------------------------
RUN cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin \
 && git config --system --add safe.directory '*'

# ---------------------------------------------------------------------------
# Extract the upstream regression test for this bug from the FIX commit,
# through a SEPARATE throwaway clone under /tmp, so the fix commit object
# never enters /app/src/.git. The extracted test lands in the image only
# (never in this repository tree) and is used by the verifier.
# ---------------------------------------------------------------------------
RUN git clone --filter=blob:none --depth 1 --no-checkout \
        https://github.com/scipy/scipy.git /tmp/scipy-golden-src \
 && cd /tmp/scipy-golden-src \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git show ${FIX_SHA}:scipy/optimize/tests/test_trustregion.py \
        > /tmp/trustregion_fix_file.py \
 && python3 - <<'PY'
marker = "    def test_trust_exact_rejects_nan_trial_point"
src = open("/tmp/trustregion_fix_file.py", encoding="utf-8").read()
i = src.index(marker)                      # the upstream test is the last
golden = src[i:].rstrip() + "\n"           # addition to this file at FIX_SHA
assert "assert result.success" in golden
assert "np.isnan" in golden or "np.nan" in golden
import os
os.makedirs("/opt/scipy-golden", exist_ok=True)
open("/opt/scipy-golden/golden_append.py", "w", encoding="utf-8").write(golden)
print("golden test extracted: %d chars" % len(golden))
PY
RUN rm -rf /tmp/scipy-golden-src /tmp/trustregion_fix_file.py \
 && test ! -e /tmp/scipy-golden-src \
 && test -s /opt/scipy-golden/golden_append.py

WORKDIR /app
COPY files/ /app/
RUN chmod a+rwX /app /app/ENVIRONMENT.md