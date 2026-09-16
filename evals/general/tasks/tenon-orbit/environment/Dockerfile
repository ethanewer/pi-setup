# tenon-orbit (v4.2 upstream-clone family): quantum dynamics with QuTiP.
#
# The upstream repository qutip/qutip is cloned SHA-pinned and installed from
# source at build time (network exists while the image builds). The trial runs
# with no network, so the installed package plus the pinned numeric stack are
# already baked into this image; the agent only needs to write a Python program
# that uses them. /app/src keeps the upstream checkout available for exploration.

FROM bench-base:python-3.12

# qutip installs a handful of C++ extensions (qutip/core/data/dense etc.), so
# it needs a C++ toolchain. apt is deliberately unpinned in this suite.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

# git-uid-1000 safety and a build identity in case the agent makes git commits.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Pinned numeric/toolchain stack for Python 3.12 (resolved against this base).
# Warm here so nothing is fetched at trial time.
RUN pip install --no-cache-dir numpy==1.26.4 scipy==1.13.1 cython==3.0.11

# Commit behind refs/tags/v5.3.1, resolved by the author via
# `git ls-remote https://github.com/qutip/qutip.git refs/tags/v5.3.1`.
# A tag can be force-moved upstream; the 40-hex hash is the pin.
ARG UPSTREAM_SHA=c95e637e0e3f9c0d3279b5fbff2c150e0de6bf9a
RUN git clone --depth 1 --branch v5.3.1 https://github.com/qutip/qutip.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && pip install --no-cache-dir .

# Warm a smoke import so the installed package is verified at build time.
RUN python3 -c "import qutip; print('qutip', qutip.__version__)"

WORKDIR /app

# Single-CPU sweep: pin any numeric thread pool to 1.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=1

COPY files/ /app/
