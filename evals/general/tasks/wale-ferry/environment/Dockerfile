FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        mariadb-server \
        mariadb-client \
        ca-certificates \
        procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Scenario fixtures (what the agent works with).
COPY files/ /app/

# Image infrastructure: database controller, deterministic seed generator,
# pristine seed script. Never a deliverable and never read by the verifier
# except through the documented dbctl interface.
COPY infra/ /opt/warehouse/
RUN chmod +x /opt/warehouse/dbctl.sh && \
    python3 /opt/warehouse/gen_data.py /opt/warehouse/order_facts.tsv

CMD ["/bin/bash"]