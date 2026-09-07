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

# MQ broker for the relay bus + client libs for the fixture/agent.
RUN apt-get update && \
    apt-get install -y --no-install-recommends mosquitto && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir paho-mqtt aiohttp numpy

# Relay fixtures: worker, survey gate, station config, broker config, maps.
COPY files/relay /app/relay
