# Last blocker before final run

item-043-main: PyStan fit running (warmup ~10%). Oracle verifier reruns both
fit_rstan.R + fit_pystan.py, scores 1.0 only if both run and cross-check.
item-043-hard: queued behind main (same fix10 watcher).

Once fix10 completes:
  python3 tools/collect_oracle2.py   # expect 520/524 green, 0 zero
  tools/finalize.sh                   # launch final run on all 524 at -n 24
