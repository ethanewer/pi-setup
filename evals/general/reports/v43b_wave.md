# v4.3b wave report — staging record

Wave: **v43b** (diversity wave of real-upstream-issue tasks)
Staged by: `stage:v43b` workflow step, branch `v4-eval`
Report timestamp: 2026-09-13T03:21:00Z (landed spec regenerated at this time)
Hand-off artifact: `specs/v43b_landed.json` (dossier verbatim + wave metadata)

This is the wave's own report. Registration of the wave was performed separately
by the operator (`reports/v43b_registration.md`, written 2026-09-13 12:02 KST) and
is intentionally kept in a different file; the two cannot collide. The both-
directions census that the registration record deferred ("appended below when it
finishes, with the observed rewards parsed out of the raw per-task logs") was run
as part of this staging pass and is reported in section 6.

---

## 1. What was mined, and from where

The v4.3 family mines **real upstream bug fixes** from the histories of real
open-source projects, per `reports/MINING_PROTOCOL_v43.md`:

* candidate commits are non-merge commits whose message references an issue or
  PR (`Fixes #N`, `Closes #N`, `(#N)`), that change at least one source file and
  at least one test file, with a source delta between 4 and 400 lines;
* each candidate is then **verified both directions** in a container on the base
  image the task will use: the reproduction must fail at the parent commit and
  pass at the fix commit, with `git reset --hard` between states and the
  protocol's documented traps (chiefly `git checkout <sha> -- <path>` staging)
  avoided;
* verified entries are written to `specs/v43_issue_pool/<repo-slug>.json`.

**Verified pool: 218 issues across 60 distinct repositories** (pool files:
`specs/v43_issue_pool/`, 60 files; every one of the 218 entries carries a
`verified` record and the pooling shows 218/218 with a non-empty verified
statement). Every pool entry records `repository`, `parent_commit`, `fix_commit`,
`upstream_issue_ref`, `source_files_changed`, `golden_test_paths`, the
reproduction and the observed failure at parent.

**Selected for authoring: 62. Landed: 62.**
32 of the 60 pool repositories are represented among the landed tasks.

---

## 2. What landed

All 62 tasks: repository, parent commit, fix commit, upstream issue reference,
domain, and the reviewer-measured image build time / image size where measured
(values as reported in the dossier; blanks = not measured by the reviewer).

| Task | Repository | Parent | Fix | Issue | Domain | Build (s) | Image (MB) |
|---|---|---|---|---|---|---|---|
| `ballast-anchorage` | BurntSushi/ripgrep | `916415857f` | `de2567a4c7` | #3180 | rust-cli | 60 | 4270 |
| `ballast-berm` | Mbed-TLS/mbedtls | `dd48f0f23f` | `7b6ddfcd25` | #9314 | systems-c | ~150 | 1128 |
| `ballast-bollard` | PyCQA/bandit | `7e6f580d6a` | `72fa5a7496` | #880 | security-tooling | 66s total | n/m |
| `ballast-boom` | PyCQA/flake8 | `2a811cc4d2` | `bdcd5c2c0a` | #1948 | program-analysis | ~120 | 666 |
| `ballast-brackish` | Z3Prover/z3 | `5fcd89bf8c` | `8fd4b73ab5` | #10621 | theorem-proving-or-solvers | ~240 | ~1500 |
| `ballast-caboose` | apache/commons-lang | `596269f16d` | `1d6ef29ce0` | #1775 | jvm-systems | ~570 | 1434 |
| `ballast-chartroom` | aquasecurity/trivy | `3dc5f8768b` | `f964fa2bb6` | #10955 | security-tooling | 180 | 1240 |
| `ballast-current` | astral-sh/uv | `6353b242d2` | `48c4357fe2` | #19799 | packaging-release | ~900-1100 | 7076 |
| `ballast-deepwater` | duckdb/duckdb | `8616efa9da` | `b94555b59e` | #25084 | data-engine | ~270 | 3470 |
| `ballast-drift` | eslint/eslint | `2417cad57d` | `8e2cb14221` | #21275 | js-tooling | 530 | n/a |
| `ballast-fathom` | git/git | `7b556aa4b8` | `1366c78c23` | git-for-windows/git#2037 | systems-c | 321 | 3174 |
| `ballast-foresheet` | gohugoio/hugo | `5f0d88b8a3` | `24d5e42ffa` | #15285 | go-infrastructure | 226 | 1428 |
| `ballast-hull` | google/guava | `7ab65d08c2` | `0007cb257b` | #3570 | jvm-systems | 106 | 997 |
| `ballast-keel` | librosa/librosa | `a0d0374370` | `86d728a4fa` | #1945 | speech-audio | 1-53 | 1270 |
| `ballast-longshore` | matplotlib/matplotlib | `91d115ec16` | `05a66bb2a4` | #29532 | scientific-python | ~300 | 1400 |
| `ballast-mooring` | netty/netty | `ba8e9e64f8` | `692d23f989` | #16958 | jvm-systems | n/m | n/m |
| `ballast-overtake` | networkx/networkx | `675034adb1` | `31ab6fd7e1` | #8899 | scientific-python | 44s | n/m |
| `ballast-pilot` | nltk/nltk | `a167389c02` | `06c0e2cc94` | #3604 | nlp | 0.4 (cached) | n/m |
| `ballast-quay` | pylint-dev/pylint | `2ef1766c39` | `16faa29d6b` | #6663 | program-analysis | 103 | 700 |
| `ballast-reach` | pypa/setuptools | `84ed591372` | `dd9f436a36` | GHSA-h35f-9h28-mq5c | packaging-release | 0.5-120 | 803 |
| `ballast-roadstead` | python-poetry/poetry | `b760721672` | `89aaee9d60` | #10807 | packaging-release | 44s (gates) | 780 |
| `ballast-rudder` | python/mypy | `5bb72b788d` | `0221c80184` | #21830 | program-analysis | 44.6 | 697.62 |
| `capstan-anchorage` | pytorch/vision | `df421b423f` | `b32ce3d020` | #9357 | computer-vision | ~60 | 1610 |
| `capstan-berm` | scikit-image/scikit-image | `6baff20f0f` | `ff3dd9468b` | #7469 | computer-vision | n/m | ~1792 |
| `capstan-bollard` | scipy/scipy | `fb96fc6e39` | `324a300aff` | #25893 | scientific-python | n/m (cached) | 2450 |
| `capstan-boom` | semgrep/semgrep | `bb89271f84` | `483878b242` | #1503 | security-tooling | 118 | 935 |
| `capstan-brackish` | sharkdp/fd | `fb0426fed1` | `5becb9d52c` | #2081 | rust-cli | 139 | 2950 |
| `capstan-caboose` | starship/starship | `d0e246802c` | `d455255e7b` | #7426 | rust-cli | n/m | n/m |
| `capstan-chartroom` | statsmodels/statsmodels | `52f10d214d` | `e30aa8337d` | #9891 | scientific-python | 150-780 | 1470 |
| `capstan-current` | syncthing/syncthing | `119d5e72ef` | `703b185982` | #10834 | go-infrastructure | 390 | 2570 |
| `capstan-deepwater` | BurntSushi/ripgrep | `ba23ced817` | `4df1298127` | #2990 | rust-cli | ~420 | 3160 |
| `capstan-drift` | Mbed-TLS/mbedtls | `5ca2218a28` | `67e696b430` | none in commit; pool "#1582" is a wrong PR — fix reached master via PR #10817 | systems-c | 256 | 1208 |
| `capstan-ebb` | PyCQA/bandit | `b790ce22f0` | `3c56109061` | #1336 | security-tooling | ~25 | 675 |
| `capstan-fathom` | PyCQA/flake8 | `d25cc10e38` | `85c2be3b52` | #1372 | program-analysis | 15.4 | 664 |
| `capstan-foresheet` | Z3Prover/z3 | `d1f10234c5` | `384d2d881f` | #10609 | theorem-proving-or-solvers | 309 | 1289 |
| `capstan-hull` | apache/commons-lang | `9d1f110190` | `10f4421456` | #1769 | jvm-systems | 143 | 1430 |
| `capstan-inlet` | aquasecurity/trivy | `f06520353f` | `3c6a1a2aca` | #10954 | security-tooling | ~300 | ~1500 |
| `capstan-keel` | astral-sh/uv | `64c73b115b` | `fab2c0c0d2` | #21261 | packaging-release | ~120 | 22300* |
| `capstan-longshore` | duckdb/duckdb | `9c21294d98` | `c306b47b18` | #25299 | data-engine | ~16 min (2 runs) | ~3350 |
| `capstan-mooring` | eslint/eslint | `ad74a8dada` | `1e641c919f` | #21251 | js-tooling | ~600 | ~2640 |
| `capstan-overtake` | explosion/spaCy | `f5d04868e1` | `94d6be8a9b` | #13876 | nlp | ~240 | ~1564 |
| `capstan-pilot` | git/git | `39bf06adf9` | `8b426c84f3` | ddiss/icyci#12 | systems-c | 400 (verify) | n/m |
| `capstan-quay` | gohugoio/hugo | `a7b93e6564` | `3a8aad6b19` | #11406 (fix PR #11407) | go-infrastructure | 865 | 4536 |
| `capstan-reach` | google/guava | `931e83f969` | `82b3e9806d` | #3501 | jvm-systems | ~118 | 951 |
| `capstan-roadstead` | jestjs/jest | `69b089574f` | `4a65c5aa40` | #16381 | js-tooling | n/m | n/m |
| `capstan-rudder` | librosa/librosa | `86d728a4fa` | `025ef7d1c7` | #1944 | speech-audio | ~10 | 1058 |
| `chainplate-anchorage` | matplotlib/matplotlib | `74c7f9a598` | `00cbd9cd32` | #28383 (PR #28486) | scientific-python | ~300 | ~1434 |
| `chainplate-berm` | netty/netty | `87d2f7506c` | `7681affcf1` | #17191 | jvm-systems | ~330 | 1290 |
| `chainplate-bollard` | networkx/networkx | `5d160909ee` | `46a639aeb9` | #8584 | scientific-python | 38 | 722 |
| `chainplate-boom` | nltk/nltk | `52227d2afe` | `27b8ad6cd5` | #3693 | nlp | 40-60 (cached) | 778 |
| `chainplate-brackish` | pylint-dev/pylint | `9242406e36` | `0f39f39e04` | #11160 | program-analysis | 3-5 min | 707 |
| `chainplate-caboose` | pypa/setuptools | `bb1b38189e` | `72974110e2` | GHSA-grgh-hr87-3jpw | packaging-release | ~200 (warm) | 819 |
| `chainplate-chartroom` | python-poetry/poetry | `e541800643` | `e6f1ded990` | #10808 | packaging-release | cached (270 cold) | 782 |
| `chainplate-current` | python/mypy | `1730c9535e` | `3f0c355b7b` | #21428 | program-analysis | 36 | 782 |
| `chainplate-deepwater` | pytorch/vision | `6940e19087` | `74d128539d` | #8887 | computer-vision | 264 | 1665 |
| `chainplate-drift` | scikit-image/scikit-image | `fff7deabe2` | `96834cf3d5` | #7648 | computer-vision | cached | n/m |
| `chainplate-ebb` | scipy/scipy | `68942fb357` | `b92b297a5a` | 25880 | scientific-python | cached | 2314 |
| `chainplate-fathom` | semgrep/semgrep | `a8b650dfe9` | `e3062fc251` | #9849 | security-tooling | ~240 | 921 |
| `chainplate-foresheet` | sharkdp/fd | `7027d45303` | `d3a500af7a` | #1900 | rust-cli | 420 | 3860 |
| `chainplate-hull` | starship/starship | `0dd5a4f402` | `91861886a7` | #7201 | rust-cli | 7200 (budget) | 5930 |
| `chainplate-inlet` | statsmodels/statsmodels | `3c102982fe` | `0a34797391` | #9805 | scientific-python | 190 | 1590 |
| `chainplate-keel` | syncthing/syncthing | `ee275fee65` | `f1d631d66e` | #10743 | go-infrastructure | 103 | 1520 |

\* `capstan-keel` `image_mb` 22300 is the raw `docker images` SIZE for the env
image; task.toml `storage_mb=20480` yet the acceptance run passed (reviewer noted).
`n/m` = not measured by the reviewer.

Difficulty of the 62 (task.toml, re-read this staging pass): **30 easy, 32
medium, 0 hard**, mean rubric total 10.3 — matches the operator's independent
registration record.

---

## 3. How each reviewer confirmed the issue is real

All 62 reviewers re-confirmed independently that the issue reproduces at the
pinned parent commit (the pool's `verified` record already documents the original
both-directions mining). The dossier's `issue_confirmed_by_reviewer` field:
**61** report a confirmed independent reproduction ("yes"/"true"/"1"), and 1
(`capstan-current`) reports "confirmed independently, both directions".

The method was uniform and reported per task, e.g.:

* a throwaway container from the task's own Dockerfile (or the base image) with a
  fresh clone; states moved **only** with `git reset --hard` (+ `git clean -fd`)
  between parent and fix, never `git checkout <sha> -- <path>` (the staging trap
  the mining protocol documents);
* the buggy code proven present/absent by inspection at the parent and fix;
* the upstream regression test re-extracted from the fix commit
  (`git show <fix>:<path>`), sha256-compared against the Dockerfile/verifier pins;
* the direct reproduction failing at parent (observed output quoted, exit codes
  measured) and passing at fix;
* the project's own unit/functional suites run on both trees;
* all authored hidden cases verified failing at parent and passing at fix;
* 19 reviewers additionally state the fix commit is the **direct child** of the
  pinned parent, 3 cite GitHub API checks, and fix-vs-parent diffs were diffed
  byte-for-byte against the authored `solution/fix.patch` where applicable.

Representative per-domain confirmations are quoted in the dossier notes for every
task; here are three of the strongest:

* `ballast-anchorage` (ripgrep #3180): an independent container at the pinned
  parent printed the exact panic (`slice index starts at 18 but ends at 17`,
  exit 101, no stdout); all 4 authored hidden cases exit 101 at parent; the
  golden regression test planted via the verifier's own mechanism fails at
  parent; `git reset --hard` to the fix prints `xbxbx` exit 0 and all hidden
  cases are byte-exact.
* `ballast-bollard` (bandit #880): at parent, `bandit -q` on a multiline
  `%`-built SQL string with `# nosec` still reports B608 at the opening line and
  exits 1; the fix-commit golden test fails with the exact upstream symptom
  (MEDIUM 26 vs 37, LOW 13 vs 24); at fix everything flips green and the full
  functional + unit suites pass.
* `chainplate-fathom` (semgrep #9849): `get_project_url()` at parent returns the
  live token (`https://gitlab-ci-token:…@…`), `clean_project_url` absent; the
  fix's `git.py` route through it eliminates the leak and all golden + hidden
  tests pass only with the fix in the tree.

---

## 4. Bypasses reviewers found and closed

Reviewers attacked each task's verifier as the trial user (agent phase runs as
root on this deployment, with egress unless a task declares otherwise — see
section 7). Counts below are per-task (a task may close several):

* **21 tasks: a demonstrated reward-1 bypass against the original verifier,
  closed before acceptance.** The demonstrated bypasses were real: a root agent
  could score 1 on an untouched tree. Classes that succeeded pre-hardening:
  * interpreter-startup shims (`sitecustomize.py`, user-site, `.pth`,
    `builtins.__import__` wrappers, meta-path finders) — closed with
    `python3 -S`, `PYTHONNOUSERSITE`, venv provenance, interpreter sha pins,
    full-python-tree manifests;
  * toolchain/binary swaps (fake `go`, `cargo`/`rustup` dispatcher, fake `mvn`,
    fake `node_modules/.bin/mocha`, answer-script `python3`, stubbed
    `target/debug/<binary>`) — closed with sha pins of the tools, ELF-header
    checks, delete-and-relink from the tree, "must be rebuilt by this
    invocation" belts;
  * compile-stage machinery hacks (gitignored `build/` artifact spoofing,
    precompiled-classes + mtime aging, `.mvn/maven.config` skip, surefire-report
    absence) — closed with forced relinks (`touch` source, `make -C tests
    clean`, `rm -rf` targets) + fresh-report evidence checks;
  * git-index deception (`assume-unchanged`/`skip-worktree` hiding tracked
    edits) — closed with `git ls-files -v` flag rejection and content hashing
    (`git hash-object`) of on-disk bytes vs parent blobs;
  * golden-test tampering (`/opt/golden` root-writable in the image) — closed
    with build-time + runtime sha256 pins of the golden files;
  * output hardcoding on visible inputs — closed with hidden cases that are
    genuinely different inputs (and where necessary random inputs generated at
    verify time, e.g. `chainplate-hull`'s `$RANDOM` background color);
  * egress lookup of the fix commit — closed per-task with
    `network_mode = "no-network"` where declared (section 7) and prevented
    everywhere by fix-commit reachability checks (single-commit object store,
    `git cat-file -e` asserts) and by withholding issue/PR/commit identifiers
    from instructions (section 8).
* **4 tasks: answer bytes were shipped inside the agent's own image and removed:**
  `capstan-brackish` (the entire fixed `src/filter/time.rs` at `/opt/golden/
  time.rs`), `chainplate-berm` (the complete fixed `JdkZlibDecompressor.java` in
  `/tmp` plus warm build logs), `chainplate-foresheet` (the whole fix-commit
  `walk.rs` at `/opt/golden/walk.rs` + `/opt/fixcheck` logs),
  `chainplate-inlet` (the fix module at `/opt/fixcheck/`). Each was scrubbed at
  build time and re-verified.
* **3 tasks declare `network_mode = "no-network"`** in `task.toml`:
  `ballast-berm`, `capstan-foresheet`, `chainplate-brackish` (all three shown to
  bite: curl/git fail in-container).
* 24 tasks reported no escapable bypass (some explicitly "none"); their
  verifiers still close the standard vectors (provenance, golden pins, hidden
  cases) and were independently probed by the reviewer.

Every fix was re-proven to bite (attack → reward 0) and the honest oracle to
still score 1, and `tools/verify_new_task.sh` was re-run clean afterwards by each
reviewer; this staging pass re-ran the full census independently (section 6).

---

## 5. What did not land, and why

`did_not_land.author_did_not_achieve` (2), everything else empty
(`author_returned_null`, `dropped_by_reviewer`,
`repositories_yielding_no_verified_issue`):

* **ballast-ebb** (explosion/spaCy): work was halted by the orchestrator before
  the deliverable was finished — status abandoned, not accepted. Both-direction
  reproduction in a task-image replica, golden-test extraction and the three
  hidden-case designs were done; nothing was written under `tasks/ballast-ebb/`,
  and neither acceptance command was run.
* **ballast-inlet** (jestjs/jest): turn cut short by the runtime before any task
  artifact was written; `tasks/ballast-inlet/` does not exist. What was
  established (host-side) is recorded in the dossier: the monorepo runner
  invocation, the golden-test failure mode at parent (11 keyPath variants), the
  provenance design (single-commit detached clone, fix commit unreachable) and
  the hidden-case plan. No reward, no verification, no build were produced.

Both entries are marked abandoned (author_did_not_achieve) so registration does
not treat them as landed.

---

## 6. Both-directions census over all 62 tasks (this staging pass)

Run by this staging step on 2026-09-13 12:15–15:17 KST as one
`tools/verify_new_task.sh` invocation over all 62 tasks (harbor oracle + nop for
each), with per-task raw logs under `/tmp/v41b-census/`. Rewards are parsed from
the **raw per-task logs** (harbor `Mean:` values and the parsed
`verifier/reward.txt` files), not from any summary line.

**Tally: 62/62 PASS.** For every one of the 62 tasks the oracle run earned
`Mean: 1.000` with `reward.txt == 1`, the nop run earned `Mean: 0.000` with
`reward.txt == 0`, `harbor_rc=0` for all 124 runs, zero harbor exceptions, and
per-task runtime 14 s – 7 m 41 s (longest: the big C/C++/Rust builds). A
complete per-task table was extracted to `/tmp/v41b-census-results.json`.

Per-task gates inside the script: `check_binary_reward.py --task` ok 62/62.
Suite-wide static gates (run once, attributed per task by the script):

| Gate | rc | Note |
|---|---|---|
| lint | 1 | names only `zephyr-forge` (a v4.3c in-flight task); 0 v4.3b tasks named |
| guard | 0 | 1020 already guarded |
| threads | 0 | 189 pinned |
| gitsafe | 0 | 194 safe |
| pippins | 1 | 1 unpinned site, not a v4.3b task (per-task filter clean for all 62; re-checked: the 62 Dockerfiles' only non-`==` pip installs are `-e /app/src` / `-e .` editable installs of the deliverable itself) |
| difficulty | 0 | 699 measured, problems=0, buckets easy 107 / medium 337 / hard 255 |

Caveats recorded honestly:

* the invocation exited 1 only because the task-list file passed to it carried a
  trailing `count: 62` line, which the script treated as two nonexistent task
  names ("no such task directory" — an artifact of this staging pass's shell
  plumbing, not of any task). The 62 real tasks all printed PASS and all raw
  logs parse green.
* an earlier, aborted census (09:20–11:55 KST the same day, run before the
  operator's registration) showed `capstan-boom` oracle=0 on one run, caused by
  a `pytest` `__pycache__` `.pyc` drift in the task's site-packages tripwire
  under heavy concurrent load (the task's verifier hash-checks `_pytest/
  __pycache__`). In this staging pass `capstan-boom` passed both directions
  (oracle 1.000 / nop 0.000), i.e. the earlier failure was a transient
  concurrent-load flake, not a task defect — but it is recorded here because the
  reviewer's flexibly-hashed tripwire is the one verifier component that can
  false-negative under extreme host contention.

---

## 7. Instruction-leak check (network-egress-aware)

Context (suite-wide, recorded in `reports/v42_wave.md` section 9 and re-observed
during this wave's review): default harbor policy on this deployment resolves
**PUBLIC**, so trials can have unrestricted egress unless a task declares
otherwise; reviewers observed live egress in trial containers. A leaked issue
number would therefore turn a debugging task into a lookup.

Method: every `instruction.md` was grepped against its pool entry for

1. the upstream issue number(s),
2. the PR number(s),
3. the fix commit (full SHA and short forms),
4. the source file(s) the upstream fix touched (`source_files_changed`),

plus a second sweep for the fix SHA and every pool issue number in any form.

**Result: 0 of 62 instructions leak an issue number, a PR number, or the fix
commit.** 31 of 62 name the parent commit — that is the revision the image
checks out, i.e. the environment itself, not a lookup key; this matches the
operator's independent finding (registration record: "Instruction leaks: 0 of
62").

Closest-to-the-line items, reported in full rather than hidden:

* `capstan-brackish` and `chainplate-foresheet` each quote a genuine crash
  traceback in which the panic location (`src/filter/time.rs:45:18`,
  `src/walk.rs:529:26`) is the very file the fix touches. That is the
  user-visible reproduction output any agent obtains by running the repro, it is
  not an identifier enabling lookup, and the fix logic itself (e.g. the
  `checked_add`/`FatalError` mechanism) is not stated. `capstan-brackish`'s
  reviewer explicitly documented this as an acceptable borderline; it is
  recorded here for the record. No edit was made: redacting the traceback would
  change the observable contract the task measures.
* several instructions name the golden/**test** file path whose basename mirrors
  the fix file's basename (`tests/lib/rules/new-cap.js` → the `new-cap` rule,
  `lib/matplotlib/tests/test_ticker.py` → the `ticker` module, etc.) or the
  public API module/import needed for the reproduction (`librosa.core.convert`,
  `statsmodels.stats.descriptivestats.describe`, `skimage.morphology.thin`).
  None of these is the fix file as a *named change target*, none enables lookup
  (no issue/PR/commit anywhere), and each reviewer documented the judgment; they
  are localization hints consistent with the tasks' easy/medium design.

**No instruction edit was needed** (no issue/PR/commit leak to redact), so no
post-edit verify re-runs were required by step 3. The two traceback cases are
reported above so registration can revisit the judgment if it disagrees.

---

## 8. Upstream-clone disjointness from Terminal-Bench 2.1

`python3 tools/check_upstream_disjointness.py` (run without `--apply` — the
`specs/upstream_sources.json` write is owned by the concurrent wave):

```
tasks_cloning_upstream=186 distinct_repositories=79 forbidden_list=68 problems=0 warnings=0
exit 0
```

The 186 cloning tasks include the 62 v4.3b tasks, the earlier v4.1–v4.3 waves,
and the concurrent v4.3c wave's in-flight directories. The intersection with the
68-repository TB2.1 forbidden list (from `specs/tb21_source_repositories.json`)
is **zero**. Independently, a per-Dockerfile scan of exactly this wave's 62
tasks found the 32 distinct repositories of this wave (plus pinned toolchain
tarballs / wheel indexes and one pinned `poetry-core` pip-from-git dependency,
none of which is a TB2.1 source repository) and **no** membership in the
forbidden list.

---

## 9. Domain-diversity measurement in Terminal-Bench 2.1 terms

Method: each of the 62 tasks carries a `domain` (dossier). For the suite-wide
count, repositories from `specs/v43_issue_pool/` (60 repos) and
`specs/v42_slots.json` (20 slots) are merged with this wave's 32 landed
repositories; domains for non-landed repos are best-effort family assignments
(flagged as such). The TB2.1 stand-in mapping below is a reasoned assignment of
each of the 68 frozen TB2.1 source repositories (extracted by
`specs/tb21_source_repositories.json` from the reference's `original-tasks/`) to
the closest of the wave's 14 domains.

**This wave: 62 tasks, 32 distinct repositories, 14 distinct domains.**
Per-domain task counts (dossier): scientific-python 8, security-tooling 6,
program-analysis 6, jvm-systems 6, packaging-release 6, rust-cli 6, systems-c 4,
computer-vision 4, go-infrastructure 4, js-tooling 3, nlp 3,
theorem-proving-or-solvers 2, data-engine 2, speech-audio 2.

**Suite as a whole (v4.3 pool + v4.2 slots + this wave): 72 distinct
repositories, all 14 domains represented** (32 landed + 28 pool-only + 12 v4.2-
only).

TB2.1 repositories each domain stands in for (53 of 68 mapped; 15 TB2.1 repos sit
outside the 14-domain shape: the benchmark's own harness
(`laude-institute/terminal-bench`, `laude-institute/t-bench`), Python web
(`pallets/flask`, `bottlepy/bottle`, `facebookresearch/hydra`), shell
(`zsh-users/zsh-autosuggestions`, `zsh-users/zsh-syntax-highlighting`), and
media/robotics/data-adjacent code (`yt-dlp/yt-dlp`, `google-deepmind/mujoco`,
`isegal/mdflib`, `amusecode/amuse`, `danielricks/textplayer`, `mmatl/pyopengl`,
`kjha02/crossenvcooperation`, `themikemerrill/personal-site`)):

| Domain | TB2.1 repos it stands in for | TB2.1 count |
|---|---|---|
| rust-cli | jvpoulos/lord_rust | 1 |
| systems-c | gcc-mirror/gcc, absint/compcert, sadiqj/ocaml, sudo-project/sudo, lc0, lodepng, doomgeneric, frotz | 8 |
| security-tooling | openwall/john, html-sanitizer-testbed, bashfuscator, test-secret-removal, purplellama | 5 |
| program-analysis | klee/klee | 1 |
| theorem-proving-or-solvers | evalmaxsat, stp, seed-prover | 3 |
| jvm-systems | apache/commons-lang, twitter/chill, lostcityrs/server | 3 |
| packaging-release | — (no direct counterpart) | 0 |
| data-engine | apache/flink, apache/spark, roaringbitmap, fsspec, esci-data, embeddings-results | 6 |
| js-tooling | — (no direct counterpart) | 0 |
| nlp | transformers, fasttext, langcodes, continuous_tokenizer, genlm-bytes, mteb, lm-evaluation-harness | 7 |
| go-infrastructure | — (no direct counterpart) | 0 |
| speech-audio | openai/whisper | 1 |
| scientific-python | astropy, cvxopt, quimb, spinningup, httpstan, pyknotid | 6 |
| computer-vision | opencv, opencv_contrib, caffe, deep-residual-networks, deepcluster, moco, locate-3d, mobilesam, imm, stair, freqpure, magsac, gltf-sample-models | 13 |

The diversity point of this wave, stated plainly: **packaging-release,
js-tooling and go-infrastructure have no direct TB2.1 counterpart at all, and
rust-cli has exactly one (lord_rust)**. Those four domains are where TB2.1
measures nothing or almost nothing, and they are the domains this wave fills
with real, verified upstream repositories (uv/poetry/setuptools, eslint/jest,
hugo/syncthing, ripgrep/fd/starship), while the other ten domains add depth by
covering real production codebases the TB2.1 samples do not include (z3, git,
mbedtls, semgrep, trivy, duckdb, scipy, statsmodels, pytorch/vision,
scikit-image, matplotlib, networkx, spacy, nltk, librosa, netty, guava,
commons-lang…).

Full per-task diversity table (task × repository × domain × TB2.1 stand-ins) is
in the landed spec; `specs/v43b_landed.json` carries `repositories` (32) and
`domain_counts` (per-task, sum 62) plus the dossier's `domain_spread` block
preserved verbatim. Note on the small discrepancy: the dossier's `domain_spread`
block reports js-tooling 4 / nlp 4, i.e. +1 each over the landed per-task counts;
those two extra slots are the abandoned `ballast-inlet` (jestjs/jest —
js-tooling) and `ballast-ebb` (explosion/spaCy — nlp), whose domains the brief's
spread includes. Per-task `domain` fields in the landed entries are
authoritative.

---

## 10. Directory census (registration prerequisite)

For all 62 tasks this staging pass confirmed: `task.toml`, `instruction.md`,
`difficulty.json`, `environment/Dockerfile`, executable `solution/solve.sh`,
`tests/test.sh`, and non-empty `tests/hidden` — **62/62**. `task.toml` parses
and difficulty matches (30 easy / 32 medium). No `.git` inside any task dir.

**No upstream source or test file committed under any task dir (62/62).** The
check searched the full task trees for the pool's `source_files_changed` and
`golden_test_paths` for that task's (repository, fix_commit) and found no
copies; no vendored upstream checkout (no `Cargo.toml`/`pyproject.toml`/
`package.json`/`go.mod`/`pom.xml` etc. at tree top level with upstream
structure); no >5MB files outside expectation in any task tree. The operator's
registration record independently reports "upstream source vendored into the
task tree 0/62".

**Golden test extracted from the fix commit at image-build time: 61/62**, and
one documented exception: `capstan-overtake` — its upstream fix commit ships NO
regression test (verified by the reviewer via GitHub API and `git diff
--name-status`), so `git show <fix>:<path>` extraction is impossible by
definition; the authored golden test was validated against the genuine fixed
upstream tree and lives at `/opt/golden` outside the agent's tree. All 61 others
extract the golden from the fix commit at build time (via `git show
${FIX_SHA}:<path>` or an equivalent throwaway-clone fetch + extraction script),
with the fix commit asserted unreachable from `/app/src` (single-commit object
store, `git cat-file -e` fail-closed).

---

## 11. Not done: contamination audit — deliberately deferred

**No contamination audit was run, and no audit verdict is claimed.** The tree is
not frozen: the concurrent v4.3c wave is still authoring 107 slots into the same
`tasks/` tree (in-flight directories observed in every suite-wide gate this
pass), and the v4.3b directories are not yet committed (registration commits
them later, over both waves). An audit over a moving tree is not a snapshot —
the v4.1 wave proved that mistake costs a re-run, and the operator's
registration record says the same ("The authoritative audit runs once, after
v4.3c finishes").

The things that CAN'T be deferred and were done here: disjointness from
TB2.1-cloned upstreams (section 8, problems=0), instruction-leak hygiene
(section 7, 0/62), directory completeness and no-vendoring (section 10), and the
both-directions census (section 6, 62/62). The byte-level block/n-gram
contamination audit (`tools/audit_independence_stream.py`) runs once, when both
waves have landed and the tree can be frozen.

Nothing was published: no harbor agent sweep, no model scores, no leaderboard,
no HF export. No changes were made to the shared specs
(`coverage_claims.json`, `coverage.json`, `difficulty.json`, `provenance.json`,
`upstream_sources.json`, `WORKFLOW.md`) and no git commits were made by this
step.