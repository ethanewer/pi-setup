# keelson-buoy: a live Postgres data-repair scenario. The task image is the
# operational database host: it carries a PostgreSQL 16 instance (managed by
# /opt/cargoctl/pgctl.sh), the deterministic scenario seed, and the incident
# artifacts under /app (ops README + stale pre-corruption snapshot). The agent
# must bring the instance up, diagnose the corruption, write a general repair
# tool, and run it. The verifier re-runs the same tool against hidden
# instances of the schema and asserts the pre-run state was left untouched.

FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client python3 python3-psycopg2 procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Infrastructure: the control script and the deterministic scenario seed are
# image-only. The seed is also what the verifier replays into scratch
# databases to recompute the pristine pre-run state.
COPY scripts/pgctl.sh /opt/cargoctl/pgctl.sh
COPY scripts/seed_cargoops.sql /opt/cargoctl/seed_cargoops.sql
RUN chmod +x /opt/cargoctl/pgctl.sh

# Everything the agent starts with.
COPY files/ /app/