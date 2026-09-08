FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
WORKDIR /app
# Toolchain + services for the Meridian Coast rendezvous cluster.
# torch (CPU) is pulled from the pytorch CPU index; the rest come from apt/pip.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         build-essential libopenmpi-dev openmpi-bin libssl-dev \
         postfix mlmmj mailutils \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch==2.14.0+cpu \
        --index-url https://download.pytorch.org/whl/cpu \
        --extra-index-url https://pypi.org/simple \
    && pip install --no-cache-dir boto3==1.43.89 awscli==1.46.1 'moto[server]==5.2.3'
COPY files/ /app/
