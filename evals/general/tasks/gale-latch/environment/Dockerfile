FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# toolchain: compiler + python headers for building the extension
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# the NEW numpy the vendored package must be ported to (no numpy 1.x present)
RUN pip install -q "numpy>=2.0,<3" "cython>=3.0,<4" setuptools

# vendored sources in their broken (numpy 1.x era) state
COPY files/ /app/

WORKDIR /app
