FROM bench-base:python-3.12

# Monorepo release changelogger bench: ships a read-only repository state
# snapshot (conventional commits, package prefix map, previous tag). The
# agent writes the CLI + visible release outputs; the verifier re-runs the
# CLI on hidden repo states and recomputes expected output from the rules.
WORKDIR /app

COPY files/ /app/