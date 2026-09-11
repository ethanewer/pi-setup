# Mining protocol for the v4.3 real-issue wave

You are mining ONE upstream repository for real, reproducible bug fixes, and
verifying each one empirically. Your output feeds task authoring, so an unverified
entry is worse than no entry: it becomes a task whose oracle cannot pass.

## What counts as a real issue

A non-merge commit in the project's own history that:

1. references a real issue or pull-request number in its message (`(#1234)`,
   `Fixes #1234`, `Closes #1234`);
2. changes at least one source file, not only docs, CI, changelog or tests;
3. changes at least one test file, so the project itself recorded a regression
   test for it;
4. has a source delta roughly between 4 and 400 lines. Smaller is trivia, larger
   is a redesign rather than a bug fix;
5. you then verify fails before the fix and passes after it.

Requirement 5 is the one that matters. A commit message claiming to fix an issue
is not evidence that it reproduces in your container.

## Finding candidates

```bash
git clone https://github.com/<owner>/<repo>.git /work/<repo>   # full history, not --depth
cd /work/<repo>
git log --format='%H%x09%s' --no-merges -n 4000 \
  | grep -iE '\(#[0-9]+\)|fix(es|ed)? #[0-9]+|clos(es|ed|ing) #[0-9]+|resolv(es|ed) #[0-9]+' \
  | while IFS=$'\t' read -r sha subj; do
      files=$(git show --name-only --format='' "$sha")
      src=$(echo "$files" | grep -cE '^(<srcdir>)/')
      tst=$(echo "$files" | grep -cE '^(tests?)/')
      [ "$src" -ge 1 ] && [ "$tst" -ge 1 ] || continue
      echo "$sha  src=$src tst=$tst  $subj"
    done | head -40
```

Adjust `<srcdir>` and the test glob to the project's actual layout. Read the
repository tree before writing the filter. A helper exists at
`/tmp/cov/mine_candidates.sh <repo-dir> <src-dir> <test-glob> [limit]` if the
layout is conventional.

Prefer issues that are self-contained, need no network to reproduce, and whose
test does not depend on a fixture the project downloads at run time.

## Verifying one candidate

Work inside a container on the base image the task will use, so you measure the
environment the task will actually run in. `bench-base:python-3.12` for Python
projects, `bench-base:ubuntu-24.04` for C, C++, Go, Rust and JVM, `bench-base:node-22`
for JavaScript.

Four traps, all of which I hit while prototyping this:

**Trap 1 — `git checkout <sha> -- <path>` stages the file.** A later
`git checkout .` restores the *staged* version, not HEAD, so you silently keep the
fix while believing you are at the parent. My first prototype reported that httpx
issue #3412 did not reproduce, and the cause was exactly this: `inspect.getsource`
showed the fix was still present in the "parent" tree. Use:

```bash
git reset --hard <sha> && git clean -fd
```

and then *prove* you are on the buggy code before drawing any conclusion, for
example by grepping the source for a symbol the fix introduced and confirming it
is absent.

**Trap 2 — `git config --global --add safe.directory /work/<repo>`.** Without it,
every git command in the container dies with "detected dubious ownership" and your
checkout silently does nothing, which looks identical to a non-reproducing bug.

**Trap 3 — install the project's FULL test dependency set.** A missing test
dependency makes `conftest.py` fail to import, and pytest reports an ImportError
that is easy to misread as a test failure. Install from the project's own
`requirements-dev.txt`, `requirements.txt`, or the test extra in `pyproject.toml`.
Then confirm the specific test actually COLLECTS before you interpret its result.

**Trap 4 — dependency versions.** A bug can be real upstream and still not
reproduce against today's dependencies, because the project deliberately does not
pin them. httpx's own `requirements.txt` says so in a comment. If the
reproduction only fails against a contemporary version of a dependency, record
that version in the entry, because the task image must pin it too.

The verification itself, for a Python project:

```bash
git reset --hard <PARENT> && git clean -fd
git checkout <FIX> -- tests/test_x.py          # bring in the project's own regression test
<install project + full test deps>
<prove the buggy code is present>
<run the reproduction>                          # MUST fail
git reset --hard <FIX> && git clean -fd
<run the same reproduction>                     # MUST pass
```

Prefer a direct reproduction over pytest where one exists. For httpx #3412 the
two-line repro `httpx.Response(200, headers=[(b'Content-Encoding', b'zstd')],
content=b'')` raising `DecodingError: Zstandard data is incomplete` was clearer
and more robust than fighting the project's pytest configuration.

## What to record

Write `/home/ee/pi-setup/evals/general/specs/v43_issue_pool/<repo-slug>.json` as a
JSON array, one entry per VERIFIED issue, each with:

```json
{
  "repository": "owner/repo",
  "upstream_issue_ref": "#3412",
  "fix_commit": "<40-hex>",
  "parent_commit": "<40-hex>",
  "base_image": "bench-base:python-3.12",
  "source_files_changed": ["httpx/_decoders.py"],
  "golden_test_paths": ["tests/test_decoders.py"],
  "golden_test_names": ["test_zstd_empty", "test_zstd_truncated"],
  "reproduction": "exact command or code that fails at parent_commit and passes at fix_commit",
  "observed_failure_at_parent": "DecodingError: Zstandard data is incomplete",
  "verified": "both directions observed, with the buggy code confirmed absent/present by inspection",
  "dependency_pins": {"zstandard": "0.22.0"},
  "install_recipe": "pip install -e '.[...]' plus the test dependencies, exact lines",
  "issue_paraphrase": "two to four sentences in your own words describing the user-visible symptom, without naming the issue, the PR, the commit or the file that fixes it",
  "fix_summary": "what the upstream fix did, for the author's reference only; must not leak into instruction.md",
  "difficulty_guess": "easy | medium | hard",
  "notes": "anything an author needs: flaky tests to avoid, tests needing network, how long the suite takes at 1 CPU"
}
```

Aim for two or three verified entries. Two well-verified entries beat six
unverified ones. If the repository yields nothing reproducible after genuine
effort, write an empty array and say why in your report; do not pad the pool with
candidates you did not verify.

## Hard rules

- Do not put anything on the forbidden list in
  `specs/tb21_source_repositories.json`, including as a transitive dependency of
  something you install. Check it.
- Do not edit any task, spec or tool. Your only writes are your own file under
  `specs/v43_issue_pool/` and scratch space under `/work` or `/tmp`.
- Do not run git commands that write to any repository under
  `/home/ee/pi-setup`. Clone into `/work`.
- Do not prune docker images or touch containers you did not create; another job
  runs on this host.
- Record the upstream issue number in the pool file, because provenance needs it,
  but write `issue_paraphrase` so that it does not appear there. The task
  instruction is built from the paraphrase, never from the issue number, because
  trials have network egress and naming the issue would let an agent look the fix
  up instead of finding it.
