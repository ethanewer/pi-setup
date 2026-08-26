FROM node:22-slim

COPY corp-root-ca.pem /usr/local/share/ca-certificates/corp-root-ca.crt
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git jq unzip zip procps python3 patch tmux \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt

# Bake pinned Pi 0.84.3 with the repo's reasoning-details patch. harbor's default
# install pulls @latest, which resolves the buggy pi-ai 0.84.3 (the upstream fix is
# not in any published release); PAgent.install() verifies this bake at runtime and
# never touches npm on bench-base images.
SHELL ["/bin/bash", "-c"]
COPY pi-ai@0.84.3-reasoning-details.patch /tmp/pi-ai-reasoning-details.patch
RUN set -ex \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | env -u NODE_VERSION bash \
    && export NVM_DIR="$HOME/.nvm" \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install 22 \
    && nvm alias default 22 \
    && npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.3 \
    && PI_AI_ROOT="$(npm root -g)/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai" \
    && { [ -f "$PI_AI_ROOT/package.json" ] || PI_AI_ROOT="$(npm root -g)/@earendil-works/pi-ai"; } \
    && grep -q '"version": "0.84.3"' "$PI_AI_ROOT/package.json" \
    && patch --batch --forward -d "$PI_AI_ROOT" -p1 < /tmp/pi-ai-reasoning-details.patch \
    && grep -q 'normalizeOpenAIReasoningDetails' "$PI_AI_ROOT/dist/api/openai-completions.js" \
    && pi --version \
    && rm /tmp/pi-ai-reasoning-details.patch
