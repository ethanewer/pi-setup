ARG PARENT_SHA=fb96fc6e396bc18fd1bfe29bfcd75966b5258e61
ARG FIX_SHA=324a300aff45a6d702fb87c1f20d8b4234050aa6

FROM bench-base:python-3.12

ARG PARENT_SHA
ARG FIX_SHA

ENV PYTHONPYCACHEPREFIX=/tmp/pycache \
    OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Toolchain for building scipy from source (base is Debian 13 trixie).
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      gcc g++ gfortran pkg-config libopenblas0-pthread libblas3 liblapack3 \
 && rm -rf /var/lib/apt/lists/*

# OpenBLAS discovery via pkg-config shim (scipy's meson looks for blas/lapack).
RUN mkdir -p /opt/openblas-pc \
 && printf 'prefix=/usr/lib/x86_64-linux-gnu/openblas-pthread\nlibdir=${prefix}\nincludedir=/usr/include\n\nName: OpenBLAS\nDescription: OpenBLAS\nVersion: 0.3.29\nLibs: -L${libdir} -lopenblas\nCflags: -I${includedir}\n' > /opt/openblas-pc/openblas.pc \
 && ln -sf libopenblas.so.0 /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so \
 && printf '/usr/lib/x86_64-linux-gnu/openblas-pthread\n' > /etc/ld.so.conf.d/openblas-pthread.conf \
 && ldconfig

RUN pip install --no-cache-dir \
      numpy==2.5.3 cython==3.3.0 meson==1.12.0 meson-python==0.21.1 ninja==1.13.2 \
      pybind11==3.1.0 pythran==0.19.0 pytest==9.1.1 hypothesis==6.168.0 \
      pooch==1.9.0 mpmath==1.4.1 pytest-timeout==2.4.0 pytest-xdist==3.8.0

# The real scipy tree at the buggy PARENT commit, pinned to its 40-hex SHA
# (shallow fetch of exactly that commit; GitHub allows fetching arbitrary SHAs).
# Submodules are required by the build (boost math, highs, qhull, ...).
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/scipy/scipy.git \
 && git -C /app/src fetch --depth 1 origin $PARENT_SHA \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "$PARENT_SHA" \
 && git -C /app/src submodule update --init --depth 1 \
 && git config --system --add safe.directory '*'

# Dev-install the tree into the persistent meson build dir. The editable
# loader maps pure-Python modules straight to /app/src and compiled
# extensions to the build dir, so later edits to .py files are live without a
# rebuild. Then complete the build: the editable install skips the HiGHS
# subproject, so run ninja to completion. The pip 'ninja' package ships a
# jobserver-only kitware fork that misbehaves outside a build jobserver;
# the distro ninja binary is installed over it (pythran calls
# /usr/local/bin/ninja by path).
ENV PKG_CONFIG_PATH=/opt/openblas-pc
RUN cd /app/src \
 && python -m pip install --no-cache-dir --no-build-isolation --no-deps \
      -e . --config-settings=builddir=/work/sci-build
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends ninja-build \
 && rm -rf /var/lib/apt/lists/* \
 && cp -f /usr/bin/ninja /usr/local/bin/ninja \
 && cd /work/sci-build && ninja -j 40

# The project's own regression test for this defect, extracted verbatim from
# the FIX commit into plain data at /opt/golden (never committed here, and the
# fix commit itself is unreachable once .git is removed below). Only the test
# file is kept in the image: it is the acceptance criterion, while the fix
# itself must never be readable by the agent.
RUN git -C /app/src fetch --depth 1 origin $FIX_SHA \
 && mkdir -p /opt/golden \
 && git -C /app/src show $FIX_SHA:scipy/optimize/tests/test_optimize.py \
      > /opt/golden/test_optimize.py \
 && test -s /opt/golden/test_optimize.py

# Strip git metadata so the fix commit and all history are unreachable from
# the checkout the agent gets, and guarantee write access for whatever uid the
# trial container runs as.
RUN rm -rf /app/src/.git \
 && chmod -R a+rwX /app \
 && chmod -R a+rwX /opt \
 && chmod -R a+rwX /work

# meson-python's editable install ships a loader that REBUILDS the project on
# every import: its staleness dry-run never reports "no work to do" for this
# tree (the HiGHS/version generators are always dirty), and the rebuild fails
# once .git has been stripped because those generators need git metadata. The
# image ships a complete build, so importing must never rebuild: patch the
# installed loader to use its static per-module mapping directly. The mapping
# resolves pure-Python files live from /app/src (an agent's edits are picked
# up with no rebuild) and compiled extensions from the completed build dir.
RUN python3 - <<'PY'
import pathlib
p = pathlib.Path('/usr/local/lib/python3.12/site-packages/_scipy_editable_loader.py')
src = p.read_text()
marker = '    def _rebuild(self) -> Node:\n        try:'
end_marker = "        install_plan_path = os.path.join("
i = src.index(marker)
j = src.index(end_marker, i)
replacement = (
    '    def _rebuild(self) -> Node:\n'
    '        # patched by the task image build: never rebuild at import; the\n'
    '        # image ships a complete build and importing must not run ninja.\n'
    '        install_plan_path = os.path.join(\n')
p.write_text(src[:i] + replacement + src[j + len(end_marker):])
print('editable loader patched to skip rebuild-on-import')
PY

WORKDIR /app

COPY files/ /app/