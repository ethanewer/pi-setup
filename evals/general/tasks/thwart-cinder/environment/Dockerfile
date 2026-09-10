# thwart-cinder: Meridian Freight analytical warehouse on PostgreSQL 16.
#
# The image ships a fully materialised, *stopped* PostgreSQL cluster at
# /srv/pgdata (database `analytics`, two index-free fact tables: events
# 2,000,000 rows, journeys 1,200,000 rows). The cluster is generated at image
# build time by environment/files/gen_warehouse.py, which initdb's the data
# directory, loads the rows, ANALYZEs and shuts down cleanly so the image
# carries a consistent, ready-to-start data directory. Nothing is running at
# trial start; the agent must deliver the start script.
#
# The performance-agnostic configuration (port, loopback only, single-threaded
# plans) is baked into the cluster's postgresql.conf at build time, so agent
# and verifier share one documented connection contract and plans are
# deterministic on the suite's single-CPU containers.

FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql postgresql-client \
        && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Scenario fixtures: schema, the slow production query, warehouse notes.
# The generator is image infrastructure: it builds the cluster and loads the
# data now, then is removed so trial agents cannot re-run it.
COPY files/ /app/

RUN mkdir -p /build && cp -r /app/warehouse /app/queries /build/ \
 && cp /app/gen_warehouse.py /build/ \
 && python3 /build/gen_warehouse.py \
 && rm -rf /build /app/gen_warehouse.py

CMD ["/bin/bash"]