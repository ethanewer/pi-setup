# cedar-summit — Tern Systems offsite negotiation stack.
#
# Four Flask microservices (coordinator + three colleague "phones") that the
# agent must bring up and talk to through the interactive dialer scripts.
# None of the services auto-start; /opt/offsite/up.sh is idempotent.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 procps curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# The microservices speak Flask (small pure-python wheel + deps).
RUN pip install --quiet --no-cache-dir --no-warn-script-location flask==3.0.3

COPY offsite/ /opt/offsite/
RUN chmod +x /opt/offsite/*.sh /opt/offsite/dial/*.sh && \
    mkdir -p /var/log/offsite && \
    python3 -c "import flask; print('flask', flask.__version__)"

WORKDIR /app
