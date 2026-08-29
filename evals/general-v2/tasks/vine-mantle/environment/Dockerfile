FROM bench-base:ubuntu-24.04

# ---- base packages (corporate CA is already baked into the bench image) ----
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        p7zip-full \
        openssl \
        john \
        git \
        ca-certificates \
        python3 \
        default-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fixtures: recovery spec, vault slot, git repo to sanitize, jar-dock Java
# sources, and an empty conventions TLS directory.
COPY files/ /app/

# Turn /app/sanitize-repo into an initialized git repo with committed history
# (the leaked daemon token is intentionally present in the working tree here).
RUN git config --global user.email "audit@mantle.example" \
 && git config --global user.name "Mantle Auditor" \
 && cd /app/sanitize-repo \
 && git init -q \
 && git add -A \
 && git commit -q -m "baseline: recovered Vine Co-op catalogue (contains leaked token)" \
 && git tag -a -m "evidence snapshot" baseline

# Confirm required tooling.
RUN 7z i >/dev/null && javac -version && openssl version && git --version

RUN chmod -R a+rX /app