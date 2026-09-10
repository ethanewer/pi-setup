# Halyard Yard

A small container-freight yard orchestration service. Containers arrive through
gate lanes, are moved about the yard by stacker cranes, are held in
temperature-controlled reefers, and roll onto outbound trains at a rail depot.

Halyard publishes Prometheus-format metrics for every one of those sub-systems.
Each sub-system has an observable failure mode, and the on-call tier expresses
those failure modes as Prometheus alerting rules.

## Layout

```
src/yard/
  metrics.py      metric-name catalogue (names + identifying label keys)
  alerting.py     the alerting contract (thresholds, windows, alert names)
  components.py   per-area samplers (gate lane, crane, reefer, depot)
  simulator.py    lockstep driver for the whole yard
docs/
  runbook.md      operational meaning of every metric, threshold and alert
monitoring/
  prometheus.yml  scrape + alerting entry point
tests/
  alerting/       promtool unit-test scenario for the alert rules
```

## Run the tests

```
python3 -m pytest
```

## Authoritative documentation

Read `docs/runbook.md`. It is the single source of truth for what each metric
means, which numbers trip an alert, and why a healthy-but-busy yard must not
page anyone.
