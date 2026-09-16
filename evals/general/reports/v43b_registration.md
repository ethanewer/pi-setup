# v4.3b registration record

Operator-run registration of the v4.3b diversity wave, executed while the v4.3c
wave was still authoring. Kept separate from `reports/v43b_wave.md`, which the
wave's own staging agent writes, so the two cannot collide.

## What was registered

62 tasks built from verified real upstream issues, across **32 distinct
repositories** and **14 domains**, from `specs/v43b_landed.json`.

| Domain | Tasks |
|---|---|
| scientific-python | 8 |
| rust-cli | 6 |
| security-tooling | 6 |
| program-analysis | 6 |
| jvm-systems | 6 |
| packaging-release | 6 |
| systems-c | 4 |
| computer-vision | 4 |
| go-infrastructure | 4 |
| js-tooling | 3 |
| nlp | 3 |
| theorem-proving-or-solvers | 2 |
| data-engine | 2 |
| speech-audio | 2 |

Repositories: BurntSushi/ripgrep, Mbed-TLS/mbedtls, PyCQA/bandit, PyCQA/flake8,
Z3Prover/z3, apache/commons-lang, aquasecurity/trivy, astral-sh/uv,
duckdb/duckdb, eslint/eslint, explosion/spaCy, git/git, gohugoio/hugo,
google/guava, jestjs/jest, librosa/librosa, matplotlib/matplotlib, netty/netty,
networkx/networkx, nltk/nltk, pylint-dev/pylint, pypa/setuptools,
python-poetry/poetry, python/mypy, pytorch/vision, scikit-image/scikit-image,
scipy/scipy, semgrep/semgrep, sharkdp/fd, starship/starship, statsmodels/statsmodels,
syncthing/syncthing.

Difficulty of the 62: 30 easy, 32 medium, 0 hard, mean rubric total 10.3. This is
the same skew the v4.3 wave showed (28 easy / 22 medium / 0 hard) and it is
inherent to the shape: a real upstream bug with a known reproduction and a
project-written regression test is usually narrow. The v4.3c wave was instructed
to withhold the reproduction from the instruction so the agent must write its own,
which is the lever available for raising difficulty without giving up real issues.

## Independent checks run before registering

Not taken from the wave's own reports.

**Instruction leaks: 0 of 62.** No instruction names its issue number, its pull
request, or its fix commit. 31 state the parent commit, which is legitimate and
necessary, because that is the revision the image checks out. This matters more
here than in an offline suite: trials have unrestricted egress (see
`reports/v42_wave.md` section 9), so a leaked issue number turns a debugging task
into a lookup.

**Structural properties, all 62:** build-time pin asserting `git rev-parse HEAD`
equals the pinned SHA 62/62; golden test present at image-build time 62/62;
system-wide `git safe.directory` 62/62; upstream source vendored into the task
tree 0/62.

Correction to how the golden figure was originally stated here. It was reported as
"extracted at image-build time 62/62", which conflated two different things,
because the check counted the presence of `/opt/golden` rather than where its
contents came from. The wave's own staging pass separated them: **61 of 62 extract
the project's own regression test from the fix commit**, and one, `capstan-overtake`
(explosion/spaCy), ships an **authored** golden test because its fix commit contains
no regression test at all. That is a legitimate exception and is documented in the
task's own Dockerfile at line 4, which still asserts
`! git cat-file -e "${FIX_SHA}^{commit}"` at line 42 so the fix stays unreachable.
The reviewer independently reproduced the underlying bug there: at parent
`f5d04868`, `spacy/displacy/__init__.py:69` imports `display` from
`IPython.core.display`, which no longer exists, so
`displacy.render(doc, style="ent", jupyter=True)` raises ImportError.

An authored golden is weaker evidence than an upstream one, because it is written by
the same process that wrote the verifier, so it should be read as 61 upstream
regression tests plus one authored reproduction rather than 62 of either.

**Fix-commit reachability.** A keyword scan left 24 tasks without a mitigation my
patterns recognised, and manual inspection of three of them found real guards the
patterns missed: `capstan-bollard` and `ballast-bollard` both `rm -rf
/app/src/.git` after extracting the golden test, and `chainplate-hull` uses
`if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit}; then` fail-the-build form rather
than the negated `! git cat-file -e` form. Three separate regex refinements each
produced false positives, so this is recorded as **not statically established for
those 24**; an empirical check (build the image, run `git cat-file -e <fix>` inside
the agent's clone) is the reliable test and is pending. For the v4.3 wave the same
property was verified empirically on two tasks and all 50 resolved into one of
three safe patterns.

## Specs

| File | Before | After |
|---|---|---|
| `specs/coverage_claims.json` | 907 | 969 (+62, all `claims_no_competencies: true`) |
| `specs/difficulty.json` measured | 637 | 699 |
| `specs/difficulty.json` suite_counts | easy 77 / medium 305 / hard 255 | easy 107 / medium 337 / hard 255 |
| `specs/coverage.json` task_index | 907 | 969 |
| `specs/upstream_sources.json` | 131 tasks / 79 repos | 180 tasks / 79 repos |
| `specs/provenance.json` external_sources | 79 | 79 |

No pre-existing difficulty bucket moved: 0 of the 637 flipped against the state
before this registration, and all 62 new entries have `bucket` equal to their own
`task.toml` difficulty. `build_difficulty.py` was not run; the entries were written
directly, because that tool recomputes buckets from rubric totals and reassigns 208
pre-existing tasks without the frozen reference. It happened once, in the v4.1
wave, and `rebuild_and_audit.py` now aborts if it recurs.

## A real bug found and fixed while registering

`tools/update_provenance.py` enumerated `specs/` with `glob('*.json')` while
`tools/check_reproducibility.py` walks it with `rglob('*')`. The recorder was
non-recursive and json-only; the checker was recursive and took every file. The
mismatch was invisible until `specs/v43_issue_pool/` added a subdirectory, and then
it produced 60 errors for the pool's json files and one more for its README.md.

Fixed to `rglob('*')` with an `is_file()` guard, matching the checker. Result:
16,247 files recorded, `check_reproducibility.py` reports 0 drift over 16,250
checked. Any future subdirectory under `specs/` is now covered by both tools
instead of only one.

## Gates

Run on a tree that also contains 107 in-flight v4.3c task directories, so the
failures below are attributed by task name rather than counted.

| Gate | Result |
|---|---|
| `check_difficulty.py --allow-unmeasured` | 699 measured, **0 problems** |
| `ensure_reward_guard.py` | 1017 guarded, 0 to patch |
| `pin_numeric_threads.py` | 188 pinned, 0 to pin |
| `ensure_git_safe_directory.py` | 190 safe, 0 to patch |
| `check_general_coverage.py` | not-retained (D1), 0 errors |
| `check_upstream_disjointness.py` | 180 tasks, 79 repositories, **0 problems**, forbidden list 68 |
| `check_reproducibility.py` | 16,250 files, **0 drift** |
| `lint_tasks.py` | 5 errors, **all v4.3c in-flight**, 0 on wave-2 tasks |
| `check_tb21_coverage.py` | 49 errors, all "task absent from matrix", **all v4.3c**, 0 on wave-2 |
| `check_binary_reward.py` | 1 NO_VERIFIER, `plimsoll-bell`, a **v4.3c** task mid-authoring |
| `pin_python_dependencies.py` | 1 unpinned requirement, `requests` in `mooring-port`, a **v4.3c** task |
| `check_task_files_tracked.py` | 1357 untracked files: the 62 wave-2 directories not yet committed plus v4.3c in-flight; clears on commit |
| `build_coverage.py` | wrote `coverage.json` with all 62 wave-2 tasks in the index, then errored on 49 v4.3c directories that have a `task.toml` but no claims entry yet |

Every failure traces to a v4.3c directory that is mid-authoring or unregistered.
None is a wave-2 defect. `build_coverage.py`'s behaviour here is worth knowing: it
writes the file and then reports the error, so `coverage.json` is correct for
everything registered and the exit code is nonzero because of tasks that are not.

## Census and export proof

**Export proof, done.** `ballast-bollard` (PyCQA/bandit) was exported from the
registration commit with `git archive HEAD` — 12 files, matching the 12 on disk —
and both harbor directions were run against the export rather than the working
tree: oracle reward 1.0, nop reward 0.0. That is what a fresh clone sees, and it is
the check that caught a real defect in the v4.1 wave, where a task-local
`.gitignore` excluded a build script the Dockerfile needed.

**Census, complete.** Both directions over all 62 tasks in four shards, with the
observed rewards parsed out of the raw per-task logs rather than read from a
summary line, because a summary is what a verifier writes about itself.

| | Result |
|---|---|
| Tasks censused | 62 |
| oracle reward `1` and nop reward `0` on the first pass | **61** |
| Static-gate failure attributed to a wave-2 task | 0 |
| Failed, then fixed and re-verified | 1 (`capstan-boom`) |
| Final | **62 / 62** |

`capstan-boom` (semgrep/semgrep) scored oracle 0 because
`tests/manifest/pytest.sha256` pinned 70 `_pytest/__pycache__/*.pyc` entries out of
142 files, and Python rewrites bytecode caches at runtime, so `sha256sum -c` could
never match on a run after the bake. Every check that mattered still passed,
including `fix commit not present in the working clone` and `exactly one commit
object reachable`. Fixed by dropping the 70 bytecode entries and keeping the 72
real source files, which is what the manifest exists for; `sha256sum -c` only
verifies listed files, so the tamper check on source is unchanged. Re-verified
oracle 1 / nop 0 and committed separately.

Three other tasks use the same manifest pattern and were checked rather than
assumed: `lighter-boom` and `nock-meridian` skip `__pycache__` when walking and the
latter sets `PYTHONDONTWRITEBYTECODE=1`; `bracket-ferry` had the equivalent fix
during the v4.3 registration.

This is the third both-directions census in this project to catch a task that had
passed its author and its independent reviewer; the v4.3 census caught three the
same way. It is also a defect class that can only appear on a second run, since the
first run in a freshly built container can have matching bytecode.

## Agreement with the wave's own staging pass

The staging agent ran its own census, leak check and disjointness check after this
registration and reached the same numbers independently: 62/62 both directions from
raw per-task harbor logs across 124 runs with 0 exceptions, 0 instruction leaks with
31 of 62 stating the parent commit, and `check_upstream_disjointness.py` reporting
`problems=0 warnings=0`. It also confirmed `capstan-boom` passes both directions in
its run, which is the fix described above holding rather than a flake. Its
`tasks_cloning_upstream` count was 186 against the 180 recorded here, because the
v4.3c wave added six more between the two runs.

The one place it found something this registration got wrong is the golden-test
figure, corrected above.

## Not done

No contamination audit. The tree is not frozen while v4.3c authors into it, and an
audit over a moving tree is not a snapshot — that mistake was made once already, in
v4.1, and cost a re-run. The authoritative audit runs once, after v4.3c finishes.

No harbor agent sweep, no model scores, no v4.3b leaderboard, nothing published to
Hugging Face.
