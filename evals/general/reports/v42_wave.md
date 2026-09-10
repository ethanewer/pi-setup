# v4.2 upstream-clone wave — registration record

The v4.2 wave authored tasks against `specs/v42_slots.json` (20 slots) that
clone a real pinned upstream repository at image-build time and put the agent
inside somebody else's codebase — the shape the frozen Terminal-Bench 2.1
reference uses in 42 of its 241 tasks and that this suite had in none of its
first 837. All 20 tasks passed both harbor directions (oracle reward 1, nop
reward 0) and independent review before this registration; nothing was
abandoned or dropped. This file records what was attempted, what landed with
its repository and pinned commit and measured build time and image size, what
each independent reviewer changed, the before/after suite composition, the
disjointness result against the 68-repository forbidden list, and the
contamination-audit verdict with every hit inspected.

Every number below is measured from the tree or copied from an independent
reviewer's per-task report where it concerns their own experiments, following
the methodology of `reports/v41_wave.md` so the two files are comparable.

## 1. Attempted vs landed

| | Count |
|---|---|
| Slots in `specs/v42_slots.json` | 20 |
| Tasks reaching registration (accepted) | 20 |
| Dropped — `not_achieved` | 0 |
| Dropped — `dropped_by_reviewer` | 0 |

All 20 landed tasks key `specs/coverage_claims.json` with
`claims_no_competencies: true` and empty `competencies`/`evidence` — they
exercise skill areas outside the tb2.1 competency inventory and claim no C- ids.
Each note records the upstream repository and the exact 40-hex pinned commit,
because that is the only place a reader can see what a task clones without
opening its Dockerfile.

## 2. The 20 landed tasks

Measured build times and image sizes are the authors'/reviewers' measured cold
`docker build --no-cache` results at 1 CPU; `build_timeout_sec` is 3x rule
checked against them in every slot (margin 16x–325x).

| Task | Repository | Pinned commit (40-hex) | Measured build | Image | What it measures |
|---|---|---|---|---|---|
| `clinker-quay` | sympy/sympy | 16fa855354eb7bcabd3fe10993841e03b1382692 | 26 s | 740 MB | SWE-bench shape: a seeded regression in the discrete-FFT submodule, localised and fixed from a failing behaviour, verified by sympy's own targeted tests plus 3 hidden reproducers |
| `clinker-mast` | encode/httpx | 26d48e0634e6ee9cdc0533996db289ce4b430177 | 13 s | 737 MB | library feature (retry transport) implemented in the clone, verified by httpx's own tests + 3 hidden files; definitions outside /app/src rejected |
| `corbel-weir` | pallets/click | 8b19813f2bfca99f1018a587a8cf54fc959f2e5d | 5.7 s | 670 MB | packaging/release: repair seeded metadata, produce sdist+wheel that install in a clean venv, verified against the installed package |
| `corbel-stave` | falconry/falcon | e18c27f454b58041c9a48e921f75182aa204d8a9 | 14.4 s | 676 MB | routing bugfix in a real micro framework, falcon's own suite + live WSGI across 3 hidden route tables |
| `derrick-tarn` | mikf/gallery-dl | 2adf2a8e0041ec55afdcc2211fd5c7ca239a9352 | 7 s | 668 MB | new extractor for a fictional site against a local mock server, run through gallery-dl's own CLI on 3 hidden fixtures |
| `ferrule-keel` | TinyCC/tinycc | d348a9a51d32cece842b7885d27a411436d7887b | 33 s | 864 MB | build a real C compiler with its own build system; the agent-built tcc is re-run on hidden programs and its own 84-test tests2 suite |
| `ferrule-berth` | arminbiere/cadical | c60730422e758ef1cebe7aeddf2dda31c996bf04 | ~110 s (1 CPU) | 882 MB | build and drive a real SAT solver; every UNSAT LRAT proof re-validated by the project's own lrat-trim |
| `pawl-bell` | official-stockfish/Stockfish | 59aae690f91d6f69aac194f447d84b4a2c3be778 | 36.6 s | 958 MB | build the engine, drive UCI to a fixed depth, exact NNUE outputs on hidden FENs + 2 non-hidden probe positions |
| `hasp-plumb` | redis/redis | 3399357e7c17b668289386b8a15a3037bc4527b1 | 56 s (author); 140 s oracle e2e | 877 MB | build and operate a real server: config, AOF/RDB persistence, eviction under a memory cap, SIGKILL-restart lifecycle |
| `ingot-flood` | id-Software/DOOM | a77dfb96cb91780ca334d0d4cfd86957558007e0 | 56 s | 1050 MB | modernise a legacy C codebase against modern glibc/gcc; verifier recompiles the repaired tree and replays timedemos under 3 build configs |
| `jerkin-cleat` | nothings/stb | 2c980bb59875b0d32144a71867fbdebb2f77cd20 | ~20 s | 912 MB | C image pipeline against stb_image/stb_image_write, byte-compared to a reference built from the same pinned headers |
| `kedge-lattice` | libvips/libvips | 426af3f44246fce9cfa8dd51a353aa4dfd48c553 | ~65–92 s | 1010 MB | meson/ninja build of a real C library; hidden pixel md5s + a hidden C program linked against the agent-built lib |
| `reeve-gate` | shadow-maint/shadow | eccf1c569c7ac3b9e3b535c91b6ed3c329e9ec8c | 87 s | 937 MB | build the autotools account suite and reach a defined /etc/passwd//shadow/group state using only its own built binaries |
| `mizzen-summit` | apache/kafka | 26b251a451ce941d3d7a55e6487bcb7f16b5ad48 | ~2.5–9 min (warm/cold) | 1930–2460 MB | navigate a 7,232-file JVM codebase, scope a change to one module, verified under gradle --offline by 3 hidden test classes |
| `nock-trestle` | trinodb/trino | 0984974677197ff76bae9fc4f4950eb30a96306a | ~65–74 s | 1227–1290 MB | find and fix a year-month interval bug in a 963k-LOC Maven tree; git-status guard + mvn -o + hidden test classes |
| `turret-moor` | yt-project/yt | f043ac898105a5b87da92226813fda96d76050da | 65 s | 1380 MB | scientific analysis with yt's own API on simulation datasets, cross-checked against independent numpy computations |
| `tenon-orbit` | qutip/qutip | c95e637e0e3f9c0d3279b5fbff2c150e0de6bf9a | 283 s | 1532–1610 MB | quantum dynamics computed in qutip's own objects; printed observable must track a monkeypatched solver result |
| `quoin-vellum` | RaRe-Technologies/gensim | ee2642b4fa26e689ba4595067504668bc7a89016 | 76 s | 1413 MB | topic modelling through gensim's own API with serialization/reload and a coherence gate a naive implementation misses |
| `plinth-wicket` | cure53/DOMPurify | 1d7460c4f8a27be825c11b1c9d346d79db32c1e5 | ~10–11 s | 970 MB | run the project's real 1227-case suite, add a bypass test, harden config; stock-parity probe + pristine-tree guard |
| `trunnel-reach` | angr/angr | f4ea23575ecb4802ede51401bb297d1cb3c1610e | 155 s | 3760 MB | symbolic execution of an authored binary via angr's API against 3 hidden binaries with different constants |

All 20 clone with `--depth 1` in `environment/Dockerfile` and assert the full
40-hex commit fail-closed (`test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"`);
every pinned SHA was re-resolved by the reviewers with `git ls-remote` and
matches the Dockerfile ARG, including the annotated-tag peel cases (stb,
gallery-dl, cadical, redis, falcon, click, sympy, gensim, qutip, kafka,
DOMPurify, angr, libvips, shadow). No upstream source bytes are vendored into
any task tree: `environment/files` holds only authored patches, generators,
fixtures and READMEs (total shipped source across the 20 tasks: 1,649 lines,
median 25.5 per task — the family stores its complexity in the pinned clone
and the image build, by design, so the v4.1-style LOC tables inverted).

## 3. What the independent reviewers changed

| Task | Reviewer change |
|---|---|
| `clinker-quay` | None. Task accepted as authored; reviewer independently re-verified every claim and probed the lazy-diagnosis-only attack (reward 0). Suite-level finding reported, not fixed: the trial container has outbound network under current harbor defaults, contradicting WORKFLOW.md's `network_mode:none` premise; per-task `no-network` engages a sidecar whose deny-all was ineffective on this host, so the field was left unset and the harness gap recorded. |
| `clinker-mast` | Tightened `tests/test.sh`: exported-members probe now requires `inspect.getsourcefile` of both retry transports to start with `/app/src/`, killing a site-packages-`sitecustomize.py` injection bypass that had scored reward 1 with `/app/src` untouched (reproduced by the reviewer; now scores 0, oracle still 1). |
| `corbel-weir` | None. Lazy-pass attack tested concretely: artifacts built from an un-repaired checkout carry `click-9.9.0` and fail the metadata + sdist-rebuild checks (reward 0); a self-written stub wheel cannot match the sha256 identity of upstream modules. |
| `corbel-stave` | (1) `instruction.md` reworded from "There is no network" to "no guaranteed network… do not attempt to download anything", accurate in both the offline and the (observed) egress-granting worlds; (2) a transient scored offline assert was added, found to flip the harbor oracle to 0, and removed — final `tests/test.sh` byte-equivalent to the author's. No-tree-cheat probe (app-only deliverable) scored 0 in both halves. |
| `derrick-tarn` | None. Reviewer probes: unregistered extractor -> 0; hardcoded visible-fixture extractor -> 0 on all hidden cases. Two neutral observations: harbor's default network policy resolves PUBLIC on this host (task unaffected, proven offline-capable), and `check_case.py` raises an unhandled JSONDecodeError on empty `-j` output (functionally safe). |
| `ferrule-keel` | None; task accepted as authored. Reviewer proved the substitution is needed (stock `make` at the pinned SHA fails on `__malloc_hook` under glibc 2.39) and that a gcc-delegating fake tcc dies at the upstream `make tests2.all` (reward 0). |
| `ferrule-berth` | Major verifier hardening. The shipped verifier byte-compared the agent's proof against a re-run of the same agent binary, so a wrapper binary appending a bogus LRAT line scored 1 while lrat-trim rejects it; and a `cp`-shortcut of a reference binary passed a `-nt` guard. Fixed: (1) ship no solver binary (deliverable must come from `make`), (2) every UNSAT LRAT proof is validated by the project's own lrat-trim compiled from the pinned clone, (3) git-integrity check on `/app/src`. All three vectors probed on the final image: honest oracle 1, corrupted proof 0, fake-no-build 0. |
| `pawl-bell` | Tightened `tests/test.sh`: two additional non-hidden probe positions driven through the raw engine with exact bestmove/score/depth required (a stub with the three hidden answers scored 1 before, 0 after). Scrub: instruction.md example transcript that leaked hidden case 1's exact answer replaced with illustrative values; a for-else indentation bug in the reviewer's own probe fixed; difficulty.json notes updated. |
| `hasp-plumb` | None; accepted as authored. One risk probed and cleared: AOF pending-rewrite inflation of `used_memory` passed at `maxmemory 64mb` with the documented 32 MB slack. |
| `ingot-flood` | Hardened `tests/test.sh` with three clauses: deliverable must be a real ELF, build.log must contain >=10 genuine `gcc -c <src>.c -o <obj>.o` lines, and run.log must contain the engine's own boot self-reports. A 20-line Python+tiny-Makefile fake had scored 1 on all three cases (untouched C code); it scores 0 after the fix, the oracle still 1. |
| `jerkin-cleat` | Tightened `tests/test.sh`: the FAIL reason must equal the reference library's own `stbi_failure_reason()` verbatim, in REPORT_FILE and stdout, extracted from the reference's REF SKIP lines. Probes: comment-spoof -> 0; pixel-correct self-contained no-upstream pipeline -> 0 (byte mismatch); stb-based no-mirror -> 0. difficulty.json notes updated. |
| `kedge-lattice` | None; accepted as authored. Reviewer independently rebuilt the constants (every hidden md5/dims/FNV matches test.sh), probed a self-contained fake vips (0 on all 9 pixel checks). |
| `reeve-gate` | Major. The original verifier's "used the built toolchain" check was a token grep; a self-contained Python editor hand-writing the shadow DBs scored 1. Fix: `strace` in the image, a new `tests/tool_use.py` trace-log analyzer attributing every DB write to one of the 30 built shadow binaries, a recursive static scan over all of /app, and every replay run under `strace -f execve`. All previously-passing exploits score 0; oracle still 1 offline and under harbor; verifier timeout raised 600 -> 900 s. |
| `mizzen-summit` | Three real defects fixed: (1) a flaky hidden test asserted a random poll key (`assertEquals(1, polled.value)` is a 50/50 coin flip) -> order-independent assert; (2) a proven gradle init.d auto-load hole (2-line `onlyIf{false}` script + stub constructors scored 1) -> guard on the .gradle-home auto-load surface; (3) a masked root build.gradle with `git update-index --assume-unchanged` skipped all tests and scored 1 -> content-hash check of every tracked file outside the module src vs HEAD blob, plus a post-run log belt. Verified both directions on all fixes. |
| `nock-trestle` | (1) instruction.md now tells the agent to leave the fix as an uncommitted working-tree change, because the verifier's git-status guard scores 0 on a clean checkout; (2) test.sh fix-summary word gate relaxed from a 2-of-{interval,year,month} conjunction to >=2 of the set, avoiding a false negative on an honest diagnosis. |
| `turret-moor` | None; accepted as authored. Variant A (self-contained numpy, never imports yt) is rejected. Residual documented: a lazy variant B that calls `yt.load` then computes in numpy passes — the loader-level static check the slot brief specifies; not tightened further to avoid over-constraining legitimate yt-based solutions. |
| `tenon-orbit` | (1) Replaced the "uses qutip" static grep with a trust-of-origin layer: every case re-runs with a `sitecustomize` monkeypatch shifting qutip's solver result by +0.10, and the printed value must track it (a decorative-sesolve spoof scored 1 before, 0 after); (2) hidden case1 parameters duplicated the instruction's example invocation, leaking an answer -> changed to (0.9, 0.6, 15.7), reference recomputed = 0.1988127. |
| `quoin-vellum` | Fixed `tests/check.py`: the raw hidden case dir (containing keys.json with the ground-truth topic words/counts) was being passed to the deliverable, i.e. the verifier handed the answer to the agent. `evaluate()` now stages `docs.txt` into a temp dir containing nothing else. A hostile deliverable that read keys.json scored 1 before and 0 after; the oracle still 1. |
| `plinth-wicket` | (1) The verifier's upstream-binding check was purely textual; a lazy self-contained jsdom sanitizer with a dead `require` scored 1. Added an 11-payload stock-parity probe: sanitize() output must be byte-identical to the clean clone's purify.cjs; the impostor now fails on every probe. (2) `/app/src` had no pristine guard: test.sh now asserts `git rev-parse HEAD` and a clean `git status --porcelain`. (3) Added hidden case D (entity-encoded control chars in scheme/`-moz-binding`). difficulty.json notes updated. |
| `trunnel-reach` | None; accepted as authored. Reviewer probed the laziest cheat (angr-decoy greps + hardcoded visible answer): passes static checks and the visible binary, scores 0 on hidden_1. Residual documented: angr's transitive pip deps are unpinned (local-path install pinned by upstream SHA — the suite-accepted class) and a determined agent could re-express the check in pure z3, which is strictly harder than the intended path. |

The only task-tree files changed during review were inside the task
directories (tests, instruction.md, difficulty.json notes); no specs file and
no other task was touched.

## 4. What did not land

Nothing. The registration handoff carried empty `not_achieved` and
`dropped_by_reviewer` lists; all 20 slots that were authored reached
registration with both harbor directions and independent review clean.

## 5. Suite composition — before and after

Measured from the tree with the same methods as `reports/v3.9_skill_gap_review.md`
and `reports/v41_wave.md`.

### Tasks

| | Before (837) | After (857) | Delta |
|---|---|---|---|
| Total tasks | 837 | 857 | +20 |

### Base images (FROM line of each environment/Dockerfile)

| Base | Before | After | Delta |
|---|---|---|---|
| `bench-base:python-3.12` | 658 | 668 | +10 |
| `bench-base:ubuntu-24.04` | 157 | 166 | +9 |
| `bench-base:node-22` | 21 | 22 | +1 |
| `texlive/texlive` | 1 | 1 | 0 |

C-toolchain and JVM builds are the reason the ubuntu share grows (tinycc,
cadical, redis, DOOM, libvips, shadow, kafka, trino + pawl-bell) while the
pure-Python library slots stay on the python base; the single node-22 slot is
DOMPurify. `cpus = 1` everywhere; `memory_mb` goes up to 10240 for the Gradle
build and 4096 for most C builds.

### Shipped source in `environment/files`

The v4.1 comparison flips deliberately: this family must not vendor upstream
source, so `environment/files` is minimal by rule (authors' patches, a mock
server, fixtures).

| Metric | The 20 new tasks |
|---|---|
| Median LOC per task | 25.5 |
| p95 LOC | 194 |
| Max LOC | 704 (`quoin-vellum` corpus generator + committed corpus) |
| Tasks >= 200 LOC | 1 |
| Sum of shipped source LOC | 1,649 |
| Median files shipped | 1 |

Language counts in new `environment/files`: `.py` 6, `.c` 5. The substantive
code an agent works on lives in the pinned upstream tree fetched at image-build
time, plus whatever the build produces, so these numbers understate the actual
work surface exactly as the family intends.

### Measured difficulty (specs/difficulty.json)

| | Before (567) | After (587) |
|---|---|---|
| easy | 49 | 49 |
| medium | 276 | 283 (+7) |
| hard | 242 | 255 (+13) |

New-task totals: min 10, mean 15.8, max 21; 13 hard / 7 medium / 0 easy. The
hard bucket is heavy because the family's whole point is dependent_stages and
reasoning_depth inside a real codebase: all 20 have `hidden_case_generalization`
>= 2 (mean 2.6), 19 have `reasoning_depth` >= 2 (mean 2.5) and
`dependent_stages` >= 2 (mean 2.6), 16 have `tool_breadth` >= 2 (mean 2.15);
`resource_pressure` (mean 0.2), `interaction_statefulness` (0.2) and
`unsafe_action_penalty` (0.05) are near-zero by design. Hard tasks all pass the
depth rule (a checked >= 2 on one of the four depth dimensions).

## 6. Registration and gates

Registered in `specs/coverage_claims.json` with `claims_no_competencies: true`,
empty `competencies`/`evidence`, and a note carrying the upstream repository +
pinned commit. `specs/coverage.json` regenerated (857 tasks, 726 competencies,
0 claimed cells for the 20; no C- id invented). `specs/difficulty.json` edited
by hand: rubric/total/notes copied from each task's own difficulty.json, timeouts
and memory/cpus read from task.toml, bucket from the rubric total against the
documented thresholds, `task_toml_difficulty` from task.toml — `build_difficulty.py`
was never run, and a canonical-JSON diff shows 0 pre-existing entries changed on
both specs files. Derived specs: `tools/check_upstream_disjointness.py --apply`
wrote `specs/upstream_sources.json`; `tools/update_provenance.py` recorded
14,268 files and the 21 external source repositories; `tools/check_reproducibility.py`
reports drift_problems=0.

Gate results, all run by the registration agent on the 857-task tree:

| Gate | Observed result |
|---|---|
| `tools/build_coverage.py` | tasks=857 competencies=726 claimed_cells=1157 errors=0 |
| `tools/check_binary_reward.py` | tasks=857 BINARY=857, rc 0 |
| `tools/selftest_binary_reward.py` | 25/25 cases pass, rc 0 |
| `tools/ensure_reward_guard.py` | would patch 0, already guarded 857, skipped 0 |
| `tools/pin_numeric_threads.py` | would pin 0, already pinned 164, skipped 0 (no --apply needed) |
| `tools/ensure_git_safe_directory.py` | would patch 0, already safe 30, skipped 0 (no --apply needed) |
| `tools/pin_python_dependencies.py` | 0 unpinned; every pip requirement pinned to a recorded version |
| `tools/lint_tasks.py` | tasks=587 legacy_v1_skipped=270 problems=0 (notes=92 informational) |
| `tools/check_general_coverage.py` | general_inventory=not-retained errors=0 |
| `tools/check_tb21_coverage.py` | 725/726 covered, 1 waived-infeasible (C-c65bea8a), problems=0; 401 second-task gaps are the documented residual |
| `tools/check_difficulty.py --allow-unmeasured` | tasks=587 buckets={easy 49, medium 283, hard 255, total 587} problems=0; the pre-existing 567 entries are still easy 49 / medium 276 / hard 242 |
| `tools/check_task_files_tracked.py` | task_files_on_disk=14210 tracked=14209 declared_large_assets=5 untracked_and_undeclared=0 declared_but_absent=0 — every task file is reachable from a fresh clone |
| `tools/check_upstream_disjointness.py` | tasks_cloning_upstream=20 distinct_repositories=21 forbidden_list=68 problems=0 warnings=0 |
| `tools/check_reproducibility.py` | checked=14271 drift_problems=0 large_assets_declared=5 not_fetched=0 |

`pin_numeric_threads.py` and `ensure_git_safe_directory.py` reported nothing to
do, so no `--apply` pass and no per-task re-verification was needed.

**Disjointness.** The 20 tasks declare 21 distinct repository identities, 0 of
which appear in the 68-repository forbidden list verified directly by set
intersection against `specs/tb21_source_repositories.json`. The 21st identity
is `github.com/adoptium/temurin25-binaries`, captured by the URL scanner
because `nock-trestle` downloads a Temurin JDK 25 binary release asset from
GitHub at build time — a binary distribution, not a source clone, and not on
the forbidden list. Every clone uses `--depth 1`, asserts the 40-hex commit,
and lives in the build path; the trial-path VCS-fetch rule also passes (0
problems).

**Clone-integrity test (v4.1 defect class).** The random draw for the wave was
`kedge-lattice`. The task was exported with `git archive` from the staged index
tree (`git write-tree` + `git archive <tree> tasks/kedge-lattice`), which is
byte-identical to what the wave commit will contain — no commit containing the
task existed before the wave commit, so the index tree is the faithful
equivalent, and `diff -r` against the working tree confirmed all 12 files
identical. Both harbor directions were then run against the export directory:
oracle reward `1` (harbor rc 0), nop reward `0` (harbor rc 0). The clone sees
exactly this content, so the task works off a clone, not only off this machine.
`check_task_files_tracked.py` additionally reports 0 problems, meaning no
task-local `.gitignore` dropped a fixture anywhere in the wave (all 345 new
files were staged by a plain `git add`).

No harbor agent sweep was run over the suite and nothing was published to
Hugging Face.

## 7. Contamination audit — observed result

Run 2026-09-10 23:38 → 2026-09-11 01:12 (94 minutes), in the foreground,
`python3 tools/audit_independence_stream.py --skip-verified-assets
--reference-root /home/ee/tb-ref/terminal-bench --reference-provenance
specs/tb21_source_repositories.json`, after every other step finished. The
tree was frozen while it ran: the tasks/ snapshot hash
`3d83e9e330bbce54d3265ea78672ad2c66a6ba262d495a870d57a241fa0f783f` over
14,231 files was identical before and after the run, and the only file created
during it is the gitignored generated report `specs/independence_report.json`
(written at 01:12, matching the observed end time). The verdict below was
observed on the run's own exit output, not assumed; this report and the
WORKFLOW.md section were written after the run finished, so they were not part
of the scanned tree (a report written before an audit can itself become a hit,
as section 8 of the v4.1 record learned).

Reference: whole terminal-bench checkout at the frozen commit
`1a6ffa9674b571da0ed040c470cb40c4d85f9b9b` (wide scope, matching the v3.4
methodology — the reference's own CI workflows, adapters and LICENSE are in
scope). 4,838 reference payloads; 15,709 of our payloads (files plus expanded
archive members), 5 hash-verified large assets skipped, 7 media fixtures
excluded by the documented encoder-signature class.

| | Count |
|---|---|
| **Exact matches** | **0** |
| **Canary matches** | **0** |
| **Source-repository matches** | **0** |
| Block matches (hard evidence, >=64 B; 32-B soft reported separately) | 10 |
| n-gram matches (14-token runs) | 15 |
| 32-byte soft matches | 709 |
| block generic/allowlisted hits | 4,354 / 5,121,387 |

The three hard-evidence classes are zero. The canary class is the strong one:
tb2.1 embeds detector strings specifically so that copying is caught, and none
is present anywhere in 15,709 payloads. The source-repository class, empty by
construction in every previous wave because `provenance.json` carried an empty
`external_sources`, now compares 21 real upstream identities against the
reference's 68 and reports zero overlap — the first time the check had anything
to compare.

**Verdict: the 20 new tasks are cleared as clean-room.** No upstream source
repository is vendored anywhere in the wave, and no new task's content matches
the reference beyond documented boilerplate/numeric-literal idioms (below).

### 7.1 All 10 block matches, with the overlapping bytes recomputed

The report records block matches without their bytes; every window below was
recomputed from both files by the registration agent (longest common substring
>= 32 bytes, both sides read from disk or decompressed for archive members).
The tool slides unaligned; an aligned reproduction misses most of them.

| Our file | Reference file | Window (ours@offset / ref@offset) | Overlapping bytes | Class |
|---|---|---|---|---|
| `bracket-quay/.../quaydoc/util.py` | `ode-solver-rk4/tests/test_outputs.py` | 224 / 1024, 65 B | `.` newline `"""` newline, `from __future__ import annotations`, `import hashlib`, `import` | Python module preamble |
| `cedar-canyon/tests/test.sh` | `adapters/algotune/template/tests/test_outputs.py` | 3156 / 1167, 57 B + 3241 / 1257, 75 B | `spec = importlib.util.spec_from_file_location("solve…` and `module_from_spec(spec)…spec.loader.exec_…` | importlib idiom (cleared in v3.4) |
| `hollow-atlas/.../san_wf_a.yml` | `.github/workflows/check-canary.yml` | 157 / 237, 80 B | `:` newline `runs-on: ubuntu-latest` newline `steps:` newline `- uses: actions/ch…` | Actions workflow skeleton |
| `hopper-wicket/.../gen_repo.py` | `.github/workflows/check-run-tests-sh-sanity.yml` | 32321 / 241, 80 B | same Actions skeleton | Actions workflow skeleton |
| `hopper-wicket/tests/hidden/H3/repo.tar.gz::gz` | `.github/workflows/ruff.yaml` | 2123 / 107, 73 B | same skeleton in the decompressed tarball stream | Actions workflow skeleton (same ci.yml member as next row, counted twice) |
| `hopper-wicket/tests/hidden/H3/repo.tar.gz::repo/.github/workflows/ci.yml` | `.github/workflows/ruff.yaml` | 75 / 107, 73 B | same skeleton | Actions workflow skeleton |
| `kite-yonder/environment/Dockerfile` | `triton-interpret/Dockerfile` | 559 / 175, 97 B + 703 / 302, 48 B | `DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-…` and `rm -rf /var/lib/apt/lists/*` newline `WORKDIR /app` `COPY` | apt Dockerfile idiom |
| `raven-core/tests/test.sh` | `adapters/cybench/run_adapter.py` | 1898 / 250, 73 B (+ 4 more 32–36 B windows) | `import subprocess` `import sys` `import tempfile` `from pathlib import`; `capture_output=True`, `)` `else:` fragment | standard-import + subprocess idiom (cleared verbatim in v3.4) |
| `stanchion-compass/.../index.html` | `broken-networking/tests/test_outputs.py` | 64 / 848, 77 B | `<meta name="viewport" content="width=device-width, in…` | HTML head boilerplate |
| `umber-yonder/.../build_fixtures.sh` | `.github/workflows/check-dockerfile-sanity.yml` | 1550 / 238, 81 B | same Actions skeleton | Actions workflow skeleton |

All ten are on pre-existing tasks (bracket-quay is v4.1; the rest predate it);
none touches a v4.2 task. Five are the Actions workflow skeleton that this
suite's release-pipeline/git-workflow tasks legitimately generate; the others
are documented Python and Dockerfile idioms already cleared in v3.4. No hit is
at 256 or 1024 bytes, none contains task content, a solution recipe, or
verifier logic.

### 7.2 All 15 n-gram matches, recomputed

The reference `LICENSE` is Apache-2.0, so license-sentence boilerplate is the
largest class. The numeric runs are described in words here, because the v4.1
record proved that quoting a matched run literally recreates the match in the
next audit's report file.

| Our file | Reference | Matching 14-token run (recomputed) | Class |
|---|---|---|---|
| `calm-canyon` x 8 (four synthetic source tarballs x `::gz` and `::./debian/copyright`) | `LICENSE` | Apache License 2.0 sentences (`…either express or implied…` / `…file except in compliance with the license…`) | license boilerplate; identical to the v3.4-documented calm-canyon hits; pre-existing |
| `clinker-quay/tests/hidden/fft_long/run.py` | `distribution-search/solution.sh` | the Fibonacci numbers one through six hundred ten, as fourteen consecutive numeric tokens | numeric-literal coincidence; NEW |
| `halyard-bell/.../H1-gate/scenario.yml` | `sqlite-with-gcov/.../distinct.test` | fourteen repeated sevens | numeric run; pre-existing |
| `halyard-bell/.../H2-stacker/scenario.yml` | `sqlite-with-gcov/.../fts5config.test` | the integers one through fourteen ascending | numeric run; pre-existing |
| `halyard-bell/.../H3-reefer/scenario.yml` | `sqlite-with-gcov/.../sqlite3_rsync.c` | fourteen repeated fours | numeric run; pre-existing |
| `lintel-winch/.../malformed.rs` | `sqlite-with-gcov/.../sqlite3recover.c` | fourteen repeated `0x00` tokens | bytes in a deliberately malformed fixture; pre-existing |
| `mizzen-summit/tests/hidden/capacity-bound/EventAccumulatorCapacityTest.java` | `LICENSE` | Apache-2.0 header sentence | license header boilerplate; NEW |
| `mizzen-summit/tests/hidden/per-key-reclaim/EventAccumulatorReclaimTest.java` | `LICENSE` | same header sentence | license header boilerplate; NEW |

The two new-wave classes, inspected closely:

- **clinker-quay / distribution-search.** The hidden FFT case uses the
  Fibonacci sequence as its third fresh input sequence (a standard
  power-of-two-adjacent test vector; the visible reproducer uses different
  sequences). The tb2.1 distribution-search solution uses the Fibonacci
  numbers as its geometric `B_candidates` search grid. Two independent authors
  chose the same famous numeric sequence as a literal list; the shared content
  is fourteen numeric tokens and nothing else. `run.py` is an FFT correctness
  check with an independent DFT oracle; the reference file is a KL-divergence
  search over probability counts. No other byte or n-gram overlap exists
  between the two files (verified: Fibonacci runs only), and clinker-quay
  appears in no block match at all.
- **mizzen-summit / LICENSE.** Both hidden Java test classes carry the standard
  ASF Apache-2.0 file header — the same header every file in apache/kafka
  carries, which the author used so the hidden tests compile inside the
  existing project layout. The matched run is the header's license-notice
  sentence, i.e. the same license-boilerplate class as calm-canyon. It contains
  no task content; the Java code below the header is all authored test logic.

### 7.3 The 32-byte soft class on the v4.2 tasks

709 soft matches total; 17 touch a v4.2 task, and every one was recomputed.
All are language/format idioms; the largest window is 72 bytes:

| Task | Window (recomputed) |
|---|---|
| `derrick-tarn` x 5 (mock gallery pages + 3 hidden sites) | `<!DOCTYPE html>` newline `<html lang="en">` newline (33 B) — HTML skeleton |
| `ferrule-keel` Dockerfile | `apt-get update && DEBIAN_FRONTEND=noninteractive` (68 B) |
| `ferrule-keel` programs/strings.c + hidden agree2 program.c | `#include <stdio.h>` newline `#include <string.h>` newline (40 B) |
| `jerkin-cleat` gen_fixtures.py | `= os.path.dirname(os.path.abspath(__file__))` (46 B) and a `)` newline `else:` fragment (36 B) |
| `jerkin-cleat` solution/pipeline.c | `#include <stdio.h>` `#include <stdlib.h>` newline (59 B) and `}` `}` `}` newline `int main(int argc, char *` (45 B) |
| `jerkin-cleat` tests/ref_pipeline.c | `*/` newline `#include <stdio.h>` `#include <stdlib.h>` (54 B and 72 B) |
| `kedge-lattice` tests/test.sh | `.h>` newline `#include <stdio.h>` `#include <stdlib.h>` (43 B) |
| `mizzen-summit` solution/feature.patch | `throw new IllegalArgumentException("…` (46 B) — Java exception idiom in the patch text |
| `turret-moor` source.npz x 3 members | the numpy `.npy` magic + descriptor header (`\x93 NUMPY ... {'descr': '<f8', 'fortran_order': False, 'shape': …}`, 61–62 B) — written by numpy itself for the same dtype |
| `turret-moor` make_dataset.py | `rng = np.random.default_rng(seed)` (43 B) — canonical numpy RNG idiom |

## 8. Publishability

- All fourteen static gates green on the 857-task tree (section 6), including
  the two gates new to this family.
- All 20 tasks proven in both directions under harbor by their independent
  reviewers before registration, and the clone-integrity directions (oracle 1 /
  nop 0) re-proven by the registration agent on a `git archive` export of a
  randomly drawn task.
- 0 exact / 0 canary / 0 source-repository matches on a verified frozen tree at
  wide reference scope, with all 10 block and 15 n-gram hits inspected, the
  overlapping bytes recomputed from both files, and all 17 soft matches
  touching the wave verified as idioms.

Not done, and deliberately not claimed: no harbor agent sweep has been run over
the 857-task suite, so there are no model scores for the 20 new tasks and no
v4.2 leaderboard; nothing has been published to Hugging Face. The negative
control was run per task as the nop half of the acceptance gate, not as a
suite-wide sweep against one frozen snapshot. The 20 new tasks are cleared as
clean-room by the audit in section 7, which means the wave is gate-clean and
contamination-clean and the suite is publishable when a sweep is run.