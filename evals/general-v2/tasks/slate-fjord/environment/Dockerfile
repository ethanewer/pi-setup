FROM bench-base:python-3.12

# Password-SSH git sync task: a local loopback SSH git server that accepts
# password authentication ONLY (pubkey disabled server-side). Only local
# network (127.0.0.1).
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        openssh-server \
        openssh-client \
        sshpass \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# SSH host keys + privilege-separation dir so the daemon can start at
# container start.
RUN mkdir -p /run/sshd /root/.ssh && ssh-keygen -A

WORKDIR /app

COPY files/ /app/

RUN chmod 0755 /app/entrypoint.sh /app/build_fixtures.sh \
    && bash /app/build_fixtures.sh && rm -f /app/build_fixtures.sh

# Provision the deploy user and start sshd (ports 22 and 2222) at every
# container start, then run whatever command the harness supplies.
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/bin/bash"]
