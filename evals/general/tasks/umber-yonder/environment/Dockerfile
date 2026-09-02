FROM bench-base:ubuntu-24.04

# Git forensics task: a local SSH-served git remote whose committed-then-deleted
# secrets must be recovered and purged. Only local network (127.0.0.1).
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-server \
        openssh-client \
        sshpass \
        python3 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# SSH host keys + runtime dir so the daemon can start at container start.
RUN mkdir -p /run/sshd /root/.ssh && ssh-keygen -A

WORKDIR /app

COPY files/ /app/

RUN chmod 0755 /app/entrypoint.sh

# Build the compromised remote bare repo (runs at image build time).
RUN bash /app/build_fixtures.sh && rm -f /app/build_fixtures.sh

# Start sshd and provision the remote user at every container start, then run
# whatever command the harness supplies (the agent session / verifier).
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/bin/bash"]
