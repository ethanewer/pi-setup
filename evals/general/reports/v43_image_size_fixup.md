# v43 image-size fix-up pass — verification report

Date: 2026-09-14 (all measurements local time; host 64 cores, /home 1.9T)
Repo: /home/ee/pi-setup (eval tree `evals/general`), branch `v4-eval`
Report writer: verification phase `report:size-fixup`

Scope: 26 fix-up tasks whose agents rewrote `environment/Dockerfile` to eliminate
copy-on-write duplicate layers (standalone `chmod`/`chown -R` RUNs after a build)
and to shrink toolchains (`--profile minimal`). This report independently
re-ran the measurements, the size-hygiene gate, and the full both-directions
verifier census. Everything below was run, not transcribed; measurements are
measured, not estimates.

All claimed reductions were < 2 GB except ballast-anchorage (2.16 GB), so per
the brief the rebuild requirement is: every task with > 2 GB reported reduction
(ballast-anchorage) plus at least six more — I rebuilt **ten** tasks in both
directions (before = Dockerfile at HEAD, after = current working-tree
Dockerfile) and measured both tags in a single `docker system df -v` snapshot.

---

## 1. Method (what was actually run)

- **Hygiene gate:** `python3 tools/check_image_size_hygiene.py` and
  `... --verbose` (results in §3).
- **Rebuild-and-measure** (10 tasks): for each of ballast-anchorage,
  ballast-berm, bracket-bell, bracket-flood, capstan-deepwater, capstan-drift,
  cistern-bell, cistern-buoy, ferrule-berth, windlass-jetty:
  - `before` context = `git show HEAD:./tasks/<t>/environment/Dockerfile` +
    current `environment/files/` (git status shows only the Dockerfile differs
    per task, so the files context is identical to HEAD);
  - `after` context = current `tasks/<t>/environment`;
  - `docker build -t v43chk-<t>-before` / `v43chk-<t>-after`, then one
    `docker system df -v` snapshot reading UNIQUE SIZE for both tags at the
    same instant (the honest same-accounting-context comparison).
  - All 10 rebuilds were layer-cache hits: the resulting image IDs are
    byte-identical to the agent tags already present on the host
    (e.g. v43chk-ferrule-berth-before == `ferrule-berth:before`
    = 7d2a0894d3f6; v43chk-ballast-anchorage-after ==
    `ballast-anchorage-after:latest`). So my rebuilds independently reproduced
    the agents' exact images, not just similar ones.
  - All my `v43chk-*` tags were removed after measurement (`docker rmi` on the
    tags I created; no prune commands, no removal of any other image/container).
- **Spot-check without rebuild** (10 more tasks whose agent tags were still
  present, via `docker images`): bracket-basin, bracket-forge, bracket-gate,
  capstan-brackish, capstan-foresheet, capstan-longshore, chainplate-anchorage,
  chainplate-hull, cistern-coral, conduit-basin. ballast-brackish and
  cistern-bight had no tags left (agents removed them after measuring; both are
  re-verified end-to-end by the census below).
- **Both-directions census:** `bash tools/verify_new_task.sh <task>` over all
  26 tasks, sharded 5 ways (5 parallel invocations, logs under
  `/tmp/v43chk/verify/shard{1..5}.console.log`). Rewards were parsed from the
  **raw verifier output** — the newest `verifier/reward.txt` written inside each
  harbor run's output dir per `<task>-oracle` / `<task>-nop` — plus each run's
  `harbor_rc` from the run console logs. (Note: the verify script's `JOBS`
  variable is computed once per invocation, so runs for the later tasks in a
  shard land under the first task's root dir; the per-task `<task>-<agent>`
  subdir names keep them unambiguous. All 52 reward files used for this report
  carry 2026-09-14 17:37–18:01 timestamps — inside my census window, not the
  agents' earlier runs.)
- **No verifier weakening:** `git diff --name-only HEAD -- tasks/<t>/tests/`
  for every one of the 26 tasks (§5). No git write command was run; nothing
  under any task directory was edited; `tools/update_provenance.py` was not
  run (a concurrent wave owns the tree).

---

## 2. Claim verification (rebuilt tasks) — my measured numbers

Apparent sizes (`docker images`, GiB) and UNIQUE (`docker system df -v`,
same-snapshot), before → after:

| task | total before | total after | measured unique before | measured unique after | agent's claimed unique before→after | verdict |
|---|---|---|---|---|---|---|
| ballast-anchorage | 4.27 | 2.11 | 3.391GB | 1.232GB | 3.39→1.23 | **matches exactly** (also the only >2 GB reduction: 2.16 GB) |
| ballast-berm | 1.18 | 1.03 | 302.9MB | 152.7MB | 0.303→0.153 | **matches exactly** |
| bracket-bell | 1.28 | 1.15 | 284.5MB | 154.3MB | 0.661→0.530 | totals exact; unique Δ 130.2MB matches claimed 130.6MB; absolute unique differs only because the agent measured standalone (their 660.6/530.4MB) vs. my shared-snapshot 284.5/154.3MB — same 130MB saving |
| bracket-flood | 1.74 | 1.34 | 824.8MB | 425.7MB | 0.91→0.91 | **discrepancy on the unique values** (see §8); their total claim 1.74→1.34 and layer-chain claim (one 426MB merged make+chmod layer, duplicate 399MB chmod layer gone) are both confirmed |
| capstan-deepwater | 3.16 | 2.38 | 2.282GB | 1.505GB | 2.282→1.505 | **matches exactly** |
| capstan-drift | 1.18 | 1.04 | 210.0MB | 70.7MB | 0.210→0.061 | before exact; after close (70.7 vs 61MB — sharing drift the agent itself flagged) |
| cistern-bell | 1.06 | 0.964 | 159.3MB | 83.0MB | 0.155→0.081 | close (Δ 76.3 vs claimed 74MB; same-class sharing drift) |
| cistern-buoy | 1.28 | 1.15 | 284.5MB | 154.3MB | 0.661→0.530 | totals exact; Δ 130.2MB vs claimed 130.6MB — matches |
| ferrule-berth | 0.877 | 0.865 | 23.93MB | 12.01MB | 0.2838 standalone / 23.93→12.01 coexisting | **matches exactly** the agent's coexisting-tags claim; their standalone 283.8MB number is the same image measured before other sharing appeared |
| windlass-jetty | 2.1 | 2.1 | 449.0MB | 448.8MB | 1.487→1.487 | Δ ≈ 0.0002GB confirms the claim that this fix (~107kB of duplicated COPY/fixture bytes) costs nothing in unique size; absolute unique 449MB vs claimed 1.487GB is pure sharing drift at my snapshot (100+ sibling images share the base/apt layers) |

Layer-history spot checks on my rebuilt *after* images confirm the duplication
elimination structurally, independent of df accounting: ballast-anchorage has a
single 626MB rustup layer carrying the `--profile minimal` install **and** its
chmods, and the old 1.41GB standalone lock-down chmod layer is now a 51.9kB
pins-only RUN; ferrule-berth's clone RUN carries the `chmod -R a+rwX /app` and
its build RUN starts with `umask 000` (no separate 11.9MB chmod layer);
bracket-flood's make+chmod is one 426MB layer and the 399MB chmod duplicate is
gone.

Spot-checked tags (not rebuilt) all match the agents' claimed after sizes:
bracket-basin 2.48, bracket-forge 2.05, bracket-gate 2.25, capstan-brackish
1.92, capstan-foresheet 1.31, capstan-longshore 2.16, chainplate-anchorage
1.24, chainplate-hull 4.99, cistern-coral 1.39, conduit-basin 1.34 (all GiB).

**No rebuilt task's measured size contradicts its agent's claim**, with the one
qualified exception of bracket-flood's unique-size values (§8).

---

## 3. Hygiene gate re-run

```
dockerfiles_scanned=1075 problems=12 advisories=113 images_measured=9
largest measured images: bracket-gate 2.2GB, bracket-forge 2.0GB, palliser-companion 1.7GB, marlinespike-wake 1.5GB, gunwale-tideway 1.3GB
```

- `problems=12`, and **all 12 ERROR lines name deferred tasks only**:
  alewife-anchorage (2), alewife-dune (2), corvette-towpath (1),
  kelson-current (1), pintle-berm (2), ropewalk-passage (1), sennit-foresheet
  (1), strake-offing (1), waterway-wharf (1).
- **0 of the 26 tasks in this pass are flagged** (grep for each pass task id in
  the verbose output returns nothing except the informational "largest
  measured images" line for bracket-gate/bracket-forge — advisory-free measured
  sizes, both well under budget; no ERROR/WARN).
- 113 advisories (WARNs) name other tasks owned by other waves (incl. several
  `rustup` full-profile warnings); per the rules these are attributed to their
  owners, not this pass.
- Note: cutwater-swell — in the brief's deferred list — is **no longer
  mentioned at all** (0 occurrences). Its Dockerfile already folds
  `chmod -R a+rwX /opt/cargo /app/src` into the same RUN as the warm cargo
  build (verified by reading the file), so the gate's standalone-chmod pattern
  does not match it. Measured; not assumed.

---

## 4. Both-directions census (re-run, raw rewards)

`bash tools/verify_new_task.sh <name>` over all 26 tasks, 5 parallel shards.

- **26/26 tasks PASS; every shard exited 0** (shard exit lines: 17:52:19,
  17:53:48, 18:01:53, 17:46:48, 17:39:07, all `exit 0`). No FAIL, no MISSING.
- **Raw `verifier/reward.txt` parsed from 52/52 harbor run output dirs,
  all created inside my census window (17:37–18:01): oracle=1 for all 26
  oracle runs, nop=0 for all 26 nop runs.**
- `harbor_rc=0` for all 52 runs (26 `harbor_rc=0 reward='1'` + 26
  `harbor_rc=0 reward='0'` lines across the shard consoles).
- Suite-wide static gates (run once per shard, cached per invocation): lint,
  guard, threads, gitsafe, pippins, difficulty all `rc=0` in all 5 shards;
  `difficulty: problems=0`. `check_binary_reward.py --task` ok for 26/26.
- Per-task PASS list: ballast-anchorage, ballast-berm, ballast-brackish,
  ballast-deepwater, ballast-longshore, bracket-basin, bracket-bell,
  bracket-channel, bracket-flood, bracket-forge, bracket-gate, capstan-brackish,
  capstan-caboose, capstan-deepwater, capstan-drift, capstan-foresheet,
  capstan-longshore, chainplate-anchorage, chainplate-hull, cistern-bell,
  cistern-bight, cistern-buoy, cistern-coral, conduit-basin, ferrule-berth,
  windlass-jetty.
- **No task that this pass touched now fails.**

---

## 5. No verifier was weakened

`git diff --name-only HEAD -- tasks/<t>/tests/` for all 26 tasks:
**26/26 report no changes under `tests/` vs HEAD.** The only working-tree
modification in any of the 26 task directories is `environment/Dockerfile`
(verified per task with `git status --short -- tasks/<t>`). No task.toml,
instruction.md, difficulty.json, solution/ or tests/ change exists to justify.
The census above additionally proves the verifiers still measure what they
claimed: oracle=1 and nop=0 on the shrunk images in every direction.

---

## 6. Honest totals and budget

- **Independent, same-snapshot unique-size reductions across the 10 tasks I
  rebuilt: 3.973 GB** (sum of before−after UNIQUE in one `docker system df -v`
  snapshot; the same 10 tasks' apparent `docker images` totals drop 3.998 GB).
  Largest: ballast-anchorage 2.159 GB, capstan-deepwater 0.777 GB,
  bracket-flood 0.399 GB.
- **Pass-wide claimed unique reductions (26 tasks, agents' reported numbers,
  not independently rebuilt): 15.296 GB** (claimed before 43.085 GB → after
  27.789 GB). I verified 10 of the 26 by rebuilding; the per-task claims for
  every one of the rebuilt tasks were confirmed (or, for bracket-flood's unique
  values, resolved in favor of the smaller image — §8). The remaining 16
  tasks' claims were confirmed only where agent tags were present (10 tasks,
  §2) plus the end-to-end census (§4) which rebuilds the env image from the
  current Dockerfile for every task.
- **Still over the 6 GB soft budget: 0 of 26.** Largest after-size in the pass
  is capstan-caboose at 5.01 GB (claimed; its tags present and matching).
- **Still over the 12 GB hard limit: 0 of 26.** (Budget counts use the agent-
  reported after totals, cross-checked against the 12 tags present locally,
  all of which match.)

---

## 7. Outstanding work — ten deferred tasks

Flagged by the gate but deliberately excluded from this pass because a
concurrent wave owns their directories. Do not forget them for the next pass:

| task | current gate status (measured today) |
|---|---|
| alewife-anchorage | 2 ERRORs (`chmod -R` on /opt/cargo and /app/src in own RUN) |
| alewife-dune | 2 ERRORs (`chown -R` /app/src, `chmod -R` /app in own RUN) |
| corvette-towpath | 1 ERROR (`chmod -R` /app/src in own RUN) |
| cutwater-swell | 0 mentions — no longer flagged (chmod already folded into the creating RUN) |
| kelson-current | 1 ERROR (`chown -R` /app/src in own RUN) |
| pintle-berm | 2 ERRORs (`chmod -R` /opt/cargo and /app in own RUN) |
| ropewalk-passage | 1 ERROR (`chmod -R` /app/src) |
| sennit-foresheet | 1 ERROR (`chmod -R` /app) |
| strake-offing | 1 ERROR (`chown -R` /app/src/build/…/meson-logs) |
| waterway-wharf | 1 ERROR (`chmod -R` /app/src) |

Reason for deferral in every case: the directory is owned by the concurrent
wave (all ten are new/`A` files at HEAD on this branch, i.e. mid-authoring);
touching them would collide. Re-run this pass's fix patterns against them after
that wave lands. cutwater-swell may already be correct and only needs a
re-check.

---

## 8. Discrepancies and caveats

1. **bracket-flood unique-size claim (only true discrepancy).** Agent reported
   `unique_before = unique_after = 0.91 GB` for old and new images measured
   simultaneously. My same-snapshot rebuild measurement reads **824.8 MB unique
   before vs 425.7 MB unique after** — a 399.1 MB unique delta. The agent's own
   notes predicted this instability (`docker system df -v` unique/shared
   bookkeeping moves with which sibling images are present) and their guarded
   claims — image total 1.74→1.34 GB, duplicate 399 MB chmod layer gone from
   the layer chain, single 426 MB merged make+chmod layer — are all confirmed
   by my rebuild (+ history). So: their *unique-value* figure contradicts my
   measurement; their *size-reduction* figure is confirmed. Reported as
   measured; resolved in favor of the smaller image.
2. **windlass-jetty absolute unique values** differ hugely from the agent's
   1.487 GB (my snapshot: 449.0→448.8 MB) because at my snapshot the base/apt
   layers are shared across 100+ images. The claimed *delta* (≈0) is confirmed
   (0.2 MB), and `docker images` totals 2.1→2.1 GB match exactly.
3. **Sharing-driven unique drift** affects every task whose absolute unique
   numbers don't land on the agent's figure (bracket-bell, cistern-buoy,
   cistern-bell, capstan-drift, ferrule-berth standalone numbers). In each case
   the same-snapshot before→after delta matches the agent's delta; the agents
   consistently reported their standalone measurements and documented the
   caveat. I treat the same-snapshot delta as the honest metric.
4. Agents' raw `verify_new_task.sh` claims were re-run by me (§4) and held;
   three prior project censuses caught posts-pass regressions, so this census
   was not skipped despite the agents' reports.

## Appendix: raw numbers backing §2 (one `docker system df -v` snapshot)

```
v43chk-* before/after UNIQUE (same snapshot):
  ballast-anchorage after 1.232GB  before 3.391GB   (rows under the agent tags ballast-anchorage-after/before:latest, same image IDs)
  ballast-berm          after 152.7MB  before 302.9MB   (rows under ballast-berm-fixed/base)
  bracket-bell          after 154.3MB  before 284.5MB
  bracket-flood         after 425.7MB  before 824.8MB   (rows under bf-new/bf-old)
  capstan-deepwater     after 1.505GB  before 2.282GB
  capstan-drift         after 70.72MB  before 210MB
  cistern-bell          after 82.99MB  before 159.3MB
  cistern-buoy          after 154.3MB  before 284.5MB
  ferrule-berth         after 12.01MB  before 23.93MB
  windlass-jetty        after 448.8MB  before 449MB
```
---

## 9. Operator addendum — one agent field was wrong, and how it was settled

The fix-up wave's structured results contain one field that contradicts the task's
actual behaviour. The `bracket-bell` agent reported `nop_reward: 1`, which would
mean a vacuous verifier: an untouched container scoring 1, so an agent could pass
without doing the work. That is the single failure mode the nop direction exists to
catch, so it was not inferred away.

The same agent's own `behaviour_preserved` narrative says "oracle reward 1 and nop
reward 0", and its `verify_exit` is 0. `tools/verify_new_task.sh` only exits 0 when
the nop reward equals 0, so a genuine nop of 1 could not have produced that exit
code. Section 4 above independently recorded a raw `verifier/reward.txt` for
`bracket-bell-nop` at 17:42 reading 0.

Settled by re-running the gate directly rather than by weighing the three
indications:

    oracle: harbor_rc=0 reward='1'
    nop:    harbor_rc=0 reward='0'
    bracket-bell PASS   (exit 0)

The field was a transcription error. The task is sound and ships.

Two spot checks were also run independently of section 4, chosen as the highest-risk
tasks in the pass rather than at random: `ballast-anchorage`, the largest reduction
at 2.159 GB, and `capstan-caboose`, the largest resulting image at 5.01 GB. Both
earned oracle reward 1 and nop reward 0 with exit 0.

### Reading the three reduction figures

Three honest numbers for the same pass differ by about 4x, and none of them is
wrong:

| Figure | GB | Basis |
|---|---|---|
| Sum of agent-claimed unique deltas | 15.295 | 26 tasks, each image measured standalone |
| Operator before/after pairs | 7.86 | 11 tasks whose tags both survived on disk, snapshots possibly mixed |
| Section 6 same-snapshot rebuild | 3.973 | 10 tasks rebuilt and measured in one `docker system df -v` |

`docker system df -v` splits an image into SHARED and UNIQUE, and that split moves
with which sibling images happen to exist at the time. Measured alone, a task's
base layers count as unique; measured alongside a hundred other images built on the
same base, they count as shared. The same-snapshot delta is therefore the
defensible floor and the standalone sum an upper bound. Quote the floor.
