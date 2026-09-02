FROM bench-base:ubuntu-24.04

# Base for vine-helix: a local "Petal" analysis node. We need openssh (the
# password auth target), sudo, procps, python3 (cProfile is stdlib), and node
# (the bundled trial checker). All available in-box; no service daemons run.
RUN apt-get update -y \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server sudo procps python3 nodejs \
 && rm -rf /var/lib/apt/lists/*

# Ship the fixtures (group members, a profile workload, a node trial checker,
# a lifecycle dir, a cleanup worker, and a terminal-banner script).
COPY files/ /app/

WORKDIR /app

# --- Authoring-time broken state (the agent must repair everything below) ----
# Group/account fixtures: group `petal`; `juna` is a member, `brok` is not.
RUN groupadd -g 4200 petal \
 && useradd -m -s /bin/bash -g 4200 juna \
 && useradd -m -s /bin/bash -g 1000 broka \
 && usermod -aG petal juna \
 # password-based login currently disabled for the petal account
 && usermod -L juna \
 # shared group area stripped: others locked out, no group/other permissions
 && chgrp -R petal /app/shared \
 && chmod 750 /app/shared \
 # group scripts had their execute/read bits wiped during the last rollout
 && chmod 000 /app/shared/scripts/digest.sh \
 && chmod 000 /app/shared/scripts/refine.sh \
 && chmod 000 /app/shared/scripts/collect.sh \
 # group scripts must belong to the group (so group members can run them once
 # execute bits are restored)
 && chown -R root:petal /app/shared/scripts \
 && chmod 755 /app \
 && chmod 711 /app/check \
 && chmod 644 /app/check/runner.mjs /app/check/trials.json