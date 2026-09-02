FROM bench-base:ubuntu-24.04

WORKDIR /app

# Git + an OpenSSH server + an sshpass client, plus python3 for the site build.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-server \
        openssh-client \
        sshpass \
        python3 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pre-generate SSH host keys and make /run/sshd exist so the daemon can start.
RUN mkdir -p /run/sshd /root/.ssh && ssh-keygen -A

COPY files/ /app/

# Build the seed fixtures: the mangled working repo, raw notes, bundles, the
# source listing, and the dedicated ssh user used for the served bare repo.
RUN bash /app/bootstrap.sh

# Convenience only; not part of the task contract.
RUN rm -f /app/bootstrap.sh