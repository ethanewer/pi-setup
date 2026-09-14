# v4.3c registration record

Operator-run registration of the v4.3c real-issue wave, committed as `3ded0b3a`.
Kept separate from `reports/v43c_wave.md`, which the wave's own staging agent
writes, so the two cannot collide and so the wave's claims and the operator's
verification of them stay distinguishable.

## What was registered

106 tasks from 107 attempted slots, across **59 distinct repositories** and **15
domains**, from `specs/v43c_landed.json`. `futtock-careen` (eslint/eslint) was not
authored and is recorded in the dossier's `did_not_land` rather than dropped
silently.

| Domain | Tasks | | Domain | Tasks |
|---|---|---|---|---|
| python-web | 13 | | packaging-release | 7 |
| scientific-python | 13 | | go-infrastructure | 7 |
| data-engine | 11 | | js-tooling | 6 |
| rust-cli | 9 | | jvm-systems | 5 |
| systems-c | 9 | | computer-vision | 5 |
| program-analysis | 8 | | nlp | 4 |
| security-tooling | 7 | | speech-audio | 1 |
| | | | theorem-proving-or-solvers | 1 |

Difficulty of the 106: **1 easy, 101 medium, 4 hard**. Suite totals move to easy
108 / medium 438 / hard 259 over 805 rubric-graded tasks, 1075 tasks overall.

The skew is the intended effect of the wave's design. v4.3b handed the agent a
reproduction and came out 30 easy / 32 medium / 0 hard. This wave withholds it, so
the agent must write its own reproduction and prove it detects the bug on a
pristine pre-fix tree and passes on the repaired one. That is the lever available
for raising difficulty without giving up real upstream issues, and it moved 101 of
106 tasks into medium.

## Independent checks run before registering

Not taken from the wave's own reports.

**Both-directions census: 106 of 106.** Sharded, over every landed task, parsing
the reward harbor wrote into `verifier/reward.txt` rather than the gate's own PASS
line. Every task earned oracle reward 1 and nop reward 0. No task needed repair and
none was waived, which is a better result than the three earlier censuses, each of
which caught at least one task that had already passed its author and its
independent reviewer.

Four tasks (`companion-berm`, `companion-flint`, `crance-bell`, `crojack-wheel`)
were censused in a separate targeted pass because their reviewers were still
running when the main census launched. Their directories were confirmed stable by
mtime before measurement, 94 to 142 minutes without an edit. Two others
(`berm-coaming`, `cringle-barquentine`) were queued while under review and turned
out to have been stable 20 and 35 minutes respectively before their census
started, verified by comparing the newest file mtime in each task directory against
the census log's start time.

**Instruction leaks: 0 of 106.** No instruction names its issue number or its fix
commit. 29 name the parent commit, which is legitimate and necessary, since that is
the revision the image checks out. This matters more here than in an offline suite:
trials have unrestricted egress (see `reports/v42_wave.md` section 9), so a leaked
issue number turns a debugging task into a lookup.

**Upstream disjointness: problems=0, warnings=0** over 238 upstream-cloning tasks
and 79 distinct repositories, against the 68-repository Terminal-Bench forbidden
list.

**Difficulty cross-check.** The distribution computed by the registrar from each
task's rubric agrees exactly with the one the staging agent derived independently
from `task.toml` metadata: 1 easy / 101 medium / 4 hard, with the staging agent
reporting 0 mismatches across 106 tasks. Two paths to the same answer.

**Landed-set agreement.** The 106 names in `specs/v43c_landed.json` and the 106
names with census `rc=0` are identical in both directions. No task landed without
being censused and none was censused without landing.

**Registration was additive.** `specs/difficulty.json` 699 → 805 and
`specs/coverage_claims.json` 969 → 1075, with every pre-existing entry diffed
against its committed state: 0 modified, 0 dropped. `tools/build_difficulty.py` was
not run, because it recomputes every task from its own task-level difficulty.json
and flips 208 pre-existing buckets.

## Gates

All exit 0: `lint_tasks`, `check_difficulty --allow-unmeasured` (805 tasks,
problems=0), `check_upstream_disjointness`, `check_tb21_coverage`,
`build_coverage` (1075 tasks, errors=0), `check_reproducibility` (16942 checked,
drift 0, not_fetched 0), `check_task_files_tracked` ("every task file is reachable
from a fresh clone").

`check_difficulty.py` without `--allow-unmeasured` exits 1 on 423 pre-existing
"oracle time not measured" errors. That is a condition of the already-committed
suite, not something this wave introduces.

## Two registrar bugs found during registration

**Indentation.** `register_task_wave.py` wrote `indent=2` where both specs use
`indent=1`. Registering 106 tasks produced a 29,922-insertion, 26,636-deletion diff
in which the actual change was invisible and nothing could be reviewed. Content was
provably unchanged, but a diff that size is how a real unintended edit hides. The
tool now detects and preserves each file's existing indentation; the corrected diff
is 3,290 insertions and 4 deletions, those 4 being the old suite counts.

**A missing flag.** `build_coverage.py` exited 1 with exactly 106 errors, one per
task just registered. The exemption for a task that deliberately claims no tb2.1
competency is a `claims_no_competencies: true` field; the registrar wrote
`competencies`, `evidence` and `note` only. Without the flag a deliberately
unclaimed task is indistinguishable from one whose author never filled the claim
in. Entries carrying the flag went 205 → 311.

## Census residue removed

`check_task_files_tracked.py` caught 26 problems that were artifacts of verification
rather than authoring: root-owned `.pytest_cache` directories under
`companion-berm` and `trawler-grove`, written by harbor trials running as root into
bind-mounted host paths, plus a stray
`tasks/alewife-anchorage-environment-export.patch` — a 1,417-byte `diff` fragment
left by an authoring agent that `update_provenance.py` had begun recording as a
suite file. There is no sudo on this host, so they were removed via a root container
bind-mount. Provenance was regenerated afterwards, 16965 → 16939 files, exactly the
26 removed.

## Contamination audit

Run on the frozen tree with the wave-3 tasks present:

    python3 tools/audit_independence_stream.py --skip-verified-assets \
        --reference-root /home/ee/tb-ref/terminal-bench/original-tasks \
        --reference-provenance specs/tb21_source_repositories.json

    files_scanned=18420 exact_matches=0 block_matches=3 block_soft_matches_32b=734
    ngram_matches=6 canary_matches=0 source_repository_matches=0

The tool exits 1 on those nine hits. **None is new and none involves a v4.3c
task.** Every flagged task was already in the previous `specs/independence_report.json`,
and all nine are adjudicated with their overlapping bytes recomputed in
`reports/v42_wave.md` section 7 and `reports/v43_wave.md`:

| Ours | Reference | Class |
|---|---|---|
| `bracket-quay/.../quaydoc/util.py` | `ode-solver-rk4/tests/test_outputs.py` | 65 B of Python import boilerplate (`from __future__ import annotations`, `import hashlib`) |
| `kite-yonder/environment/Dockerfile` | `triton-interpret/Dockerfile` | 97 B `DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends` |
| `stanchion-compass/.../index.html` | `broken-networking/tests/test_outputs.py` | 77 B HTML `<meta name="viewport">` head boilerplate |
| `clinker-quay/tests/hidden/fft_long/run.py` | `distribution-search/solution.sh` | Fibonacci 1..610 as fourteen numeric tokens |
| `halyard-bell` H1/H2/H3 `scenario.yml` | `sqlite-with-gcov` test files | repeated sevens / 1..14 ascending / repeated fours |
| `lintel-winch/tests/hidden/gamma/malformed.rs` | `sqlite3recover.c` | fourteen repeated `0x00` in a deliberately malformed fixture |
| `ballast-current/.../hc_valid_roundtrip.rs` | `sqlite3recover.c` | same hex-dump class |

No block match is at 256 or 1024 bytes, none contains task content, a solution
recipe, or verifier logic. The strong signals — exact matches, canary matches and
source-repository matches — are all zero.

This run was committed as `3ded0b3a` while the audit was still in its n-gram
phases, on the reasoning that the block phase had completed clean over 18420
payloads and seven gates were green. The audit result above is what closes that
item; the commit did not.

## Still outstanding

- The image-size fix-up wave is a **separate commit** and was deliberately kept out
  of `3ded0b3a`. All 26 of its targets now clear `check_image_size_hygiene.py`, and
  independent measurement of the 11 tasks that still had before/after image pairs on
  disk showed 7.86 GB of unique-size reduction, 38.2%. Its own report agent's
  numbers have not yet been compared against that.
- Ten flagged tasks were deferred out of the fix-up wave because reviewers owned
  their directories: `alewife-anchorage`, `alewife-dune`, `corvette-towpath`,
  `cutwater-swell`, `kelson-current`, `pintle-berm`, `ropewalk-passage`,
  `sennit-foresheet`, `strake-offing`, `waterway-wharf`. Nine are still flagged.
  Five of them have now been censused at their current image size, so shrinking them
  requires re-running the both-directions gate on each.
