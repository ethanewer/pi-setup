# reed-haven: a mailing-list provisioning exercise around the deterministic
# in-house listd daemon. The daemon, its behavior reference, the raw sign-up
# sheet, and the visible command stream are shipped as /app assets; the agent
# authors the canonical config at /etc/listd/config.toml (via an idempotent
# provisioning deliverable) and replays the visible stream.

FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN mkdir -p /etc/listd && chmod +x /app/listd.py
