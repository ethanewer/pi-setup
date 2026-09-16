# Hopper Wicket — cut a release

`seabolt` is a small fixture-sync package. Its repository at `/app/project` has
full git history, a clean worktree and a passing test suite — a normal mid-life
project. What it lacks is a working release process: nobody can cut a versioned
release, get a changelog, or prove which bytes shipped.

Your job is to write **`/app/release.py`**: a reusable, general release CLI.
The grader will run it against *fresh* git repositories of the same shape as
`/app/project` — different histories, different tags, different commit
messages — so it must implement the rules below, not any particular history.

The pipeline: (1) derive the next semver from the conventional commits since
the last release tag, (2) generate a changelog grouped by change type with
breaking changes called out, (3) build a reproducible source artifact and
record its byte hash in a provenance file, (4) create a version tag at HEAD.

Everything is local: `git`, `python3`, `gzip` and common shell tools are
installed; there is no network and no hosted release service to talk to.

## CLI contract

```
python3 /app/release.py <REPO_DIR> <OUT_DIR>
```

- `<REPO_DIR>` — a git working tree (contains `.git`) like `/app/project`.
- `<OUT_DIR>` — the output directory; created if missing.
- Exit code `0` on success. If the repository has **no releasable commits**,
  print `no releasable commits` (exactly that text) to stderr and exit with
  code `3`, creating nothing. Other failures exit non-zero with a diagnostic
  on stderr.
- Diagnostics on stdout/stderr are free-form; the grader does not parse them.

## Release rules

### 1. Base version

List tags with `git tag`. A *release tag* is a tag whose name matches
`v<major>.<minor>.<patch>` exactly — three dot-separated integers, nothing
else (so `v1.2.0-rc.1` is **not** a release tag, and neither is `release-1`).
The base version is the greatest such tag under (major, minor, patch) ordering.
If the repository has no release tags, the base version is `0.0.0`.

### 2. Commit range

If a base release tag exists, the range is the commits reachable from `HEAD`
but not from the base tag — in git terms `<base-tag>..HEAD`. If there is no
base release tag, the range is every commit reachable from `HEAD`.

### 3. Parsing commits

For each commit in the range, take the first line of the commit message as the
*subject* and the remaining lines as the *body*. A commit is **conventional**
when its subject matches

```
type[(scope)][!]: subject-text
```

exactly: `type` is one or more lowercase ASCII letters, the scope is optional
and is any text not containing parentheses, the `!` is optional, then a colon,
then one space, then non-empty subject text. Anything else — merge notices,
sentences with leading capitals, free text — is not a conventional commit and
is ignored entirely (it does not appear in the changelog and does not affect
the version).

A conventional commit is **breaking** when either of these is true:

- the `!` marker is present immediately before `: ` (for example
  `feat!:`, `refactor(api)!:`); or
- any **body** line, after optional leading whitespace, starts with
  `BREAKING-CHANGE:` or `BREAKING CHANGE:` (case-insensitive). A line that
  merely *contains* that text later on (e.g. `note: this is not a
  breaking-change: …`) does not count.

### 4. Next version

Bump the base version:

- if any counted commit is breaking → increase major, zero minor and patch
  (e.g. `2.4.1` → `3.0.0`);
- else if any counted commit has type `feat` → increase minor, zero patch
  (`2.4.1` → `2.5.0`);
- else, if there is at least one counted commit → increase patch
  (`2.4.1` → `2.4.2`).
- no counted commits at all → nothing to release (see the CLI contract).

The version is written as `X.Y.Z` with no leading `v`.

### 5. Changelog

Write `<OUT_DIR>/CHANGELOG.md` with this exact line structure (a blank line
separates every block; sections with no commits are omitted entirely):

```
# Changelog

## [1.2.3] - 2024-02-14

### Breaking Changes

- <subject-text> (<full-40-hex-sha>)

### Added

- <subject-text> (<full-40-hex-sha>)

### Fixed

- <subject-text> (<full-40-hex-sha>)

### Changed

- <subject-text> (<full-40-hex-sha>)
```

- `## [VERSION] - DATE`: `VERSION` is the version from step 4; `DATE` is the
  date of the `HEAD` commit formatted `%Y-%m-%d`, exactly what
  `git log -1 --format=%cd --date=short HEAD` prints.
- Each counted commit appears under **exactly one** heading: breaking commits
  under `Breaking Changes`, `feat` commits under `Added`, `fix` commits under
  `Fixed`, and every other conventional commit under `Changed`. (A breaking
  `feat` or `fix` appears only under Breaking Changes, not under its type
  heading too.)
- `<subject-text>` is the text after the `: ` — do not include the type or
  scope — with trailing whitespace trimmed. `<full-40-hex-sha>` is the
  commit's full object id.
- Within each heading, commits are ordered newest-first by committer Unix
  timestamp; ties are broken by ascending full sha.
- The file ends with exactly one newline after the final bullet.

### 6. Artifact

The reproducible source artifact is the tree at `HEAD` archived with git and
compressed with gzip using **exactly** this pipeline (the grader rebuilds it
independently and compares byte hashes):

```
git -C <REPO_DIR> archive --format=tar HEAD | gzip -n > <OUT_DIR>/release-<version>.tar.gz
```

### 7. Provenance

Write `<OUT_DIR>/provenance.txt` with exactly these five lines, in this order:

```
version: 1.2.3
commit: <full-40-hex-sha-of-HEAD>
tag: v1.2.3
artifact: release-1.2.3.tar.gz
artifact_sha256: <lowercase 64-hex sha256 of the artifact bytes>
```

### 8. version.txt

Write `<OUT_DIR>/version.txt` containing the bare version and a trailing
newline, e.g. `1.2.3\n`.

### 9. Tag

Create an **annotated** tag at `HEAD`:

```
git -C <REPO_DIR> tag -a v1.2.3 -m "Release 1.2.3"
```

## What is already there

- `/app/project` — the seabolt repository: ~15 files across `src/`, `tests/`,
  `data/` and config, 8 commits, tag `v0.3.0`; `make test` from the repo root
  runs a green unittest suite. Use it to smoke-test your tool; running the
  tool on it only adds a tag.
- `/app/releases` does not exist yet; create it as your smoke-test output if
  you like.
- `git`, `gzip`, `python3` are on PATH. No other toolchain is needed.

## Constraints

- Work only in/under `/app` (aside from the tag your tool adds inside a
  repository it is pointed at).
- Your tool may not depend on anything under `/app/project` being a specific
  branch name, a specific file layout, or a specific number of commits — the
  grading repositories are copies the harness supplies, with different
  histories and tags, and the tool must work on them untouched.
- The grader runs the tool with `python3`, so `/app/release.py` must work
  when invoked that way. Nothing under `/tests/` is visible to you or your
  tool.