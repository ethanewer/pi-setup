FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y \
    git nginx openssh-server openssl curl \
    && rm -rf /var/lib/apt/lists/*

# --- deployment identity: git user + SSH keypair used by the deployment client ---
RUN set -e; \
    mkdir -p /srv/git /srv/www /app/deploy/keys /etc/nginx/ssl; \
    useradd -m -s /bin/bash git; \
    mkdir -p /home/git/.ssh; \
    ssh-keygen -t ed25519 -f /app/deploy/keys/id_ed25519 -N '' -C 'git-deploy-key'; \
    cp /app/deploy/keys/id_ed25519.pub /home/git/.ssh/authorized_keys; \
    chown -R git:git /home/git /srv/git /srv/www; \
    chmod 700 /home/git/.ssh; \
    chmod 600 /home/git/.ssh/authorized_keys

WORKDIR /app