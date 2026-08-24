FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y \
    git nginx openssh-server openssl curl jq \
    && rm -rf /var/lib/apt/lists/*

# --- deployment identity: git user + SSH keypair used by the deployment client ---
RUN set -e; \
    mkdir -p /srv/git /app/deploy/keys /etc/nginx/ssl; \
    useradd -m -s /bin/bash git; \
    mkdir -p /home/git/.ssh; \
    ssh-keygen -t ed25519 -f /app/deploy/keys/id_ed25519 -N '' -C 'git-deploy-key'; \
    cp /app/deploy/keys/id_ed25519.pub /home/git/.ssh/authorized_keys; \
    chown -R git:git /home/git; \
    chmod 700 /home/git/.ssh; \
    chmod 600 /home/git/.ssh/authorized_keys

# --- adversarial seeding: deploy dirs pre-exist but are ROOT-owned with stale content.
# The hook (which runs under the `git` account) must be able to overwrite these. ---
RUN set -e; \
    mkdir -p /srv/www/main /srv/www/staging /srv/www/dev; \
    echo 'STALE_ROOT_MAIN_LOCK_9' > /srv/www/main/index.html; \
    echo 'STALE_ROOT_STAG_LOCK_8' > /srv/www/staging/index.html; \
    echo 'STALE_ROOT_DEV_LOCK_7'   > /srv/www/dev/index.html; \
    chmod 755 /srv/www; chmod 755 /srv/www/main /srv/www/staging /srv/www/dev

WORKDIR /app