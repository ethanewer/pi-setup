FROM bench-base:python-3.12
WORKDIR /app

# MQ broker for the relay bus + client libs for the fixture/agent.
RUN apt-get update && \
    apt-get install -y --no-install-recommends mosquitto && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir paho-mqtt aiohttp numpy

# Relay fixtures: worker, survey gate, station config, broker config, maps.
COPY files/relay /app/relay
