# ---------------------------------------------------------------------------
# crance-bell: real scipy/scipy cloned at the PARENT of upstream fix
# 6dbd21acb0ab2ad22a06b6351f83a47743d8b0b5 ("MAINT: stats.wilcoxon: correct
# sf tail choice logic", upstream issue #26026). The agent gets the genuine
# buggy tree and must write its own failing reproduction, localise and fix
# the bug. It is never told the issue number, the commit, or the file to
# change. The fix commit is never fetched into /app/src: the object store
# holds exactly the one pinned parent commit, so the answer is not readable
# anywhere in the image. The project's own regression test for the bug ships
# in tests/golden/ and is mounted only at verification time (the agent phase
# mounts neither /tests nor /solution), so the agent never sees it either.
# ---------------------------------------------------------------------------
ARG UPSTREAM_SHA=d9b45feb89659479d666e1818bc1aa556292659e
ARG FIX_SHA=6dbd21acb0ab2ad22a06b6351f83a47743d8b0b5

FROM bench-base:python-3.12

ARG UPSTREAM_SHA
ARG FIX_SHA

# The trial container runs on one vCPU; pin every numeric thread pool so the
# scipy/numpy code paths do not oversubscribe the core.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# bench-base:python-3.12 is Debian 13 (trixie) with no C/C++ toolchain and no
# BLAS; the scipy build needs compilers + OpenBLAS/LAPACK at image-build time.
# OpenBLAS 0.3.29 is found via pkg-config: trixie ships
# /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so.0 but no .pc file,
# so we write a shim and symlink libopenblas.so -> libopenblas.so.0.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc g++ gfortran pkg-config \
        libopenblas0-pthread libblas3 liblapack3 git \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so.0 \
           /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so \
 && printf 'prefix=/usr/lib/x86_64-linux-gnu/openblas-pthread\nlibdir=${prefix}\nincludedir=/usr/include\nName: OpenBLAS\nDescription: OpenBLAS (pthread)\nVersion: 0.3.29\nLibs: -L${prefix} -lopenblas\nCflags: -I${includedir}\n' \
      > /opt/openblas.pc

# Pinned dependency set (era-matched to the pinned commit's Aug-2026 build
# requirements: meson-python>=0.15.0, Cython>=3.2.0, pybind11>=2.13.2,
# pythran>=0.18.1, numpy>=2.0.0). Everything the editable build and the
# project's own test runner need.
RUN pip install --no-cache-dir \
      numpy==2.2.6 \
      Cython==3.3.0 \
      meson-python==0.21.1 \
      ninja==1.13.2 \
      pybind11==3.1.0 \
      pythran==0.19.0 \
      pytest==9.1.1 \
      hypothesis==6.168.0 \
      pooch==1.9.0 \
      pytest-xdist==3.8.0 \
      pytest-timeout==2.4.0 \
      mpmath==1.4.1 \
      setuptools==80.9.0 \
      wheel==0.45.1 \
      packaging==25.0

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy PARENT commit only, fix commit unreachable -------
# `git init` + one depth-1 fetch of the pinned SHA means the object store in
# /app/src holds ONLY the parent commit. The upstream fix commit - which the
# agent must not be able to look up - is never fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/scipy/scipy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git rev-list --all --count)" = "1" \
 && git submodule update --init --depth 1

# The upstream regression test for this bug (test_gh26026) is NOT baked into
# the image: it lives in tests/golden/ in the task tree and harbor mounts it
# only when the verifier runs, so the agent (whose phase mounts neither
# /tests nor /solution) can never read the answer or the reproduction. The
# fix commit is never fetched anywhere in this image build at all.

# ---- the expensive editable build, once, as a cached image layer -----------
# The agent only edits pure-Python files; meson-python's editable install
# serves them live from /app/src, so the trial never rebuilds. Ownership is
# fixed in the SAME RUN as the build (layer written once) so the trial works
# as uid 1000 without doubling the tree in a later layer.
RUN cd /app/src \
 && PKG_CONFIG_PATH=/opt pip install -e . --no-build-isolation --no-cache-dir \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src

RUN mkdir -p /app && chmod 777 /app

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]