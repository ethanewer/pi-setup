FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN rm -rf /app/webapp && mkdir -p /app/webapp

# Deploy script with a branch guard: only feature-eu may deploy to the eu target.
RUN cat > /app/webapp/deploy.sh <<'SH'
#!/usr/bin/env bash
set -e
BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
if [ "$BRANCH" != "feature-eu" ]; then
  echo "deploy refused: branch '$BRANCH' is not approved for the eu deployment" >&2
  exit 1
fi
mkdir -p /srv/app
cp config.json /srv/app/config.json
printf 'branch=%s\ncommit=%s\n' "$BRANCH" "$COMMIT" > /srv/app/DEPLOYMENT
echo "deployed $BRANCH ($COMMIT)"
SH
RUN chmod +x /app/webapp/deploy.sh

# Git history: main has the prod config; feature-eu adds the eu config.
RUN cd /app/webapp && \
    git init -q -b main && \
    printf '{"env":"prod","api":"https://api.prod.example.com"}\n' > config.json && \
    printf 'print("webapp started")\n' > app.py && \
    git add -A && \
    git -c user.email=bench@example.com -c user.name=bench commit -q -m "init webapp (prod baseline)" && \
    git checkout -q -b feature-eu && \
    printf '{"env":"eu","api":"https://api.eu-west.example.com"}\n' > config.json && \
    printf 'EU localization notes: support is handled by the EU team.\n' > eu_notes.md && \
    git add -A && \
    git -c user.email=bench@example.com -c user.name=bench commit -q -m "configure EU environment" && \
    git checkout -q main
