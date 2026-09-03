FROM bench-base:python-3.12

# Gilded Bandit: online learning for a nonstationary multi-armed bandit with
# delayed feedback and an abrupt drift.  Deterministic seeded simulation;
# the policy module + eval report are the deliverables.
WORKDIR /app

COPY files/ /app/

# Sanity: the harness runs standalone on this image.
RUN python3 /app/env/bandit_env.py info --params /app/params.json