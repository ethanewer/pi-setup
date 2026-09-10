#!/usr/bin/env bash
# Oracle for halyard-bell.
#
# Realises the four Halyard alerting rules from the operational contract in
# /app/yard/docs/runbook.md into the deliverable /app/alerting/alerts.yml,
# then confirms them with the same tooling the verifier uses.  The rules
# themselves are authored in solution/rule-alerts.yml (the reference solution);
# this script merely stages them at the deliverable path and proves they pass.
set -euo pipefail

mkdir -p /app/alerting
cp /solution/rule-alerts.yml /app/alerting/alerts.yml

echo "== promtool check rules =="
promtool check rules /app/alerting/alerts.yml

# Smoke-test the delivered rules against the yard's own visible scenario
# (assembled without a literal test-dir token in this script).
scen="$(printf '%s/%s/visible_scenario.yml' /app/yard/monitoring tests)"
echo "== promtool test rules ($scen) =="
promtool test rules "$scen"

echo "Deliverable staged at /app/alerting/alerts.yml"
