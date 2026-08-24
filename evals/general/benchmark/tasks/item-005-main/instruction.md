You are engineering a Core War ("Redcode") warrior for a legacy tournament that runs on the **pMARS** simulator. A tournament harness stored at `/app/tournament/benchmark.sh` battles a your submitted warrior against three fixed opponents in `/app/tournament/opponents/` and computes an aggregate score.

Read `/app/tournament/INSTALL.md` first — it contains the legacy build instructions, the Redcode notes, and the exact submission/harness contract. Below is a summary.

## What you must deliver

1. **pMARS binary at `/app/pmars`.** The pMARS source package (Debian source tarball) is already extracted at `/app/pmars-src/` (a reliable fallback copy is available there). Build it for this headless server using the tournament / no-display (`-DSERVER`) variant, and install the produced binary at the exact absolute path `/app/pmars` that the harness expects. Do not assume the binary already exists there.

2. **Warrior at `/app/tournament/mine.red`.** Write a Redcode warrior program so that `mine.red` is a valid pMARS Redcode file. See `/app/pmars-src/examples/simple_warrior.red` and `/app/pmars-src/doc/redcode.ref` for the language.

3. **Optimize.** Score against the three opponents in `/app/tournament/opponents/` with:

   ```
   cd /app/tournament
   ./benchmark.sh mine.red
   ```

   The harness runs each battle with a fixed seed (`-f`), so results are reproducible for a given file. Watch the reported `points` metric.

## Metric

The harness reports `points` defined as

```
points = (wins + 0.5 * draws) / games      # across all opponents, per battle
```

- `wins` = rounds your warrior survives and the opponent does not; `draws` = rounds both survive (tie). Both are "not lost" and both count. Your goal is to maximize this aggregate.

## Exact requirements (validated by the grader)

- The harness must be invocable exactly as `./benchmark.sh mine.red` with your warrior as the first argument.
- The binary must be at exactly `/app/pmars`.
- The warrior must be at exactly `/app/tournament/mine.red`.
- Do not modify anything under `/app/tournament/opponents/` (immutable inputs; the grader treats them as fixed).

Build it, install it at `/app/pmars`, write and tune `mine.red`, and maximize the harness's `points` output. The scorer reruns the harness (same settings, same opponents) against your submitted warrior at verify time.