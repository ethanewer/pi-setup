#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
if [ -f /srv/app/config.json ] && [ -f /srv/app/DEPLOYMENT ]; then
  if grep -q '"env" *: *"eu"' /srv/app/config.json && \
     grep -q '"api" *: *"https://api.eu-west.example.com"' /srv/app/config.json && \
     grep -q '^branch=feature-eu$' /srv/app/DEPLOYMENT; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
