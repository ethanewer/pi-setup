You are engineering a Core War ("Redcode") warrior for a legacy pMARS tournament. Read `/app/tournament/INSTALL.md` first — it contains the legacy build instructions, the Redcode notes, and the exact submission/harness contract. A summary follows.

## Environment

- pMARS source package extracted at `/app/pmars-src/` (trusted fallback of the original Debian source tarball; build it yourself — a binary is not preinstalled).
- Harness: `/app/tournament/benchmark.sh`, which battles your warrior against the fixtures in `/app/tournament/opponents/` (`imp.red`, `dwarf.red`, `paper.red`) and prints an aggregate `points` metric.
- Redcode reference: `/app/pmars-src/doc/redcode.ref`; starter warrior: `/app/pmars-src/examples/simple_warrior.red`.

## Deliverables (exact paths, validated at verify time)

1. Build pMARS for this headless server (no X11 display available — use the tournament / no-display server variant) and install the binary at **exactly** `/app/pmars`.
2. Write your warrior to **exactly** `/app/tournament/mine.red` (a valid Redcode file).
3. Run and iterate against the visible opponents:

   ```
   cd /app/tournament
   ./benchmark.sh mine.red
   ```

## Metric

points = (wins + 0.5 * draws) / games, aggregated over all opponents. Maximize it. The harness uses `-f` (fixed seed derived from warrior bytes), so every battle is reproducible for a given file.

## Hard-mode specifics (read carefully)

- The three opponents under `/app/tournament/opponents/` are **immutable**: do not modify, replace, delete, or add files in that directory. The grader hashes them.
- The final scoring run also includes an additional **held-back opponent** whose Redcode you cannot inspect. To score top marks your warrior must be robust against an *unknown* opponent, not tuned merely to beat the three visible ones. Engineers who only overfit to the visible fixtures will not reach the top of the score distribution.
- Before submitting, stress-test generalization: verify your warrior also performs well when the harness is pointed at an unseen directory of opponents, e.g.
  `OPP_DIR=/some/copy ./benchmark.sh mine.red` (the exact harness flag set stays the same).
- Keep the exact submission & invocation contract: binary at `/app/pmars`, warrior at `/app/tournament/mine.red`, harness run exactly as `./benchmark.sh mine.red`.

Final state: harness invocable as above, `mine.red` and `/app/pmars` in place, and the highest `points` you can reach.