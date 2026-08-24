# Pipeline state

Done:
- generation (524 task specs in plan.json)
- pilot skill-bucket-23 (16 tasks)
- full-gen 47 buckets

In flight:
- bench-repair (59 tasks) - chunks feeding
- oracle-pass-1 watcher (chunks sequentially)
- bench-fix-tests (258 broken test.sh rewrite)

Waiting/later:
- lint re-pass
- consolidated oracle re-pass of failures
- final run p_agent+PAgent openrouter deepseek/deepseek-v4-flash-0731 at -n 20 -k 1

Update: oracle pass 1 done (317 passed/62 failed/86 errored of 465).
- 258 broken test.sh -> all rewritten valid (0 bash errors)
- re-oracle of non-passers running (207 tasks, chunked)
- bench-repair: chunks 0/2/5 done; 3/4 = last hard items
- bench-fill-empty: 16 remaining empties created
- Next: final lint after all land -> re-oracle non-passers -> FINAL RUN:
  PYTHONPATH=$PWD/agents harbor run -p tasks -a p_agent:PAgent \
    -m openrouter/deepseek/deepseek-v4-flash-0731 -n 20 -k 1 -y -o jobs

User instruction (new): after initial benchmark run, audit grades/tasks for
validity, fix, iterate until confident, then one FINAL full run; optionally
lower concurrency when needed.


Current: 519 lint-ok, 4 bad, 1 missing. Fix flows running.
Next (when converge):
1) re-lint; expect 523 ok
2) FULL oracle sweep @ concurrency 8 across all 523 tasks, chunked
3) audit report: classify failures by root cause; fix; iterate
4) benchmark run p_agent openrouter deepseek/deepseek-v4-flash-0731
5) audit grades validity (item results vs task expectations)
6) fix tasks, iterate; then FINAL full run
Workflows this round: plan-check (clear), fix-tests (done), fill-empty (3/4),
repair (4/6), deep-fix (0/8 grinding).
