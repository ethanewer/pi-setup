# Umbral Inlet — monorepo release changelogger from conventional commits

Your team maintains a monorepo whose releases are driven by **conventional
commits**. You must write a small stdlib-only CLI that turns a repository
state snapshot into per-package **semver bump** decisions and canonical
**CHANGELOG.md** files, and run it once to produce the visible release
outputs.

## Deliverables (all under /app)

1. `/app/changelogger.py` — the CLI (see contract below).
2. `/app/release/bumps.json` — bump summary produced by running the CLI on
   the visible state with the command given further down.
3. `/app/release/core/CHANGELOG.md` — changelog for the `core` package.
4. `/app/release/app/CHANGELOG.md` — changelog for the `app` package.
5. `/app/release/tools/CHANGELOG.md` — changelog for the `tools` package.

## Repository state (shipped read-only under /app/repo_state)

- `/app/repo_state/commits.jsonl` — one JSON object per line: `{"hash":
  "<string>", "message": "<full commit message, may contain \n>", "files":
  ["<path>", ...]}`. Lines are already in chronological order. A line that is
  not a JSON object of exactly those three fields (any type mismatch, or
  unparseable JSON) is **dropped** before parsing.
- `/app/repo_state/packages.json` — `{"<name>": {"path": "<prefix>",
  "version": "X.Y.Z"}}`. `path` is a path prefix used to map changed files to
  packages; `version` is the current released version.
- `/app/repo_state/last_tag.json` — `{"tag": "<previous release tag>"}`. The
  tag string is echoed into every changelog; a missing or unparseable
  `last_tag.json` is a fatal error (exit 1).

## CLI contract

```
python3 /app/changelogger.py <repo_state_dir> --date YYYY-MM-DD --out <dir>
```

- Reads `packages.json`, `last_tag.json`, `commits.jsonl` from
  `<repo_state_dir>`.
- Creates `<dir>` if needed and writes `<dir>/bumps.json` plus, for every
  package that receives a bump, `<dir>/<name>/CHANGELOG.md`.
- Exit 0 on success. Exit 1 on any error (missing/unreadable state file,
  malformed `packages.json` or `last_tag.json`, `--date` not matching
  `YYYY-MM-DD`). Errors go to stderr.
- Python 3 standard library only. No network. Deterministic — no randomness,
  no wall-clock time, and the `--date` value is the **only** date used.

## Conventional commit grammar (exact)

Only the **first line** of `message` is the *header*; the remaining lines are
the *body*. The header must be exactly one of:

```
type: description
type(scope): description
type(scope)!: description
type!: description
type!(scope): description
```

- `type` is lowercase letters only (`[a-z]+`). Recognized types: `feat`,
  `fix`, `docs`, `chore`, `refactor`, `perf`, `test`, `style`, `build`,
  `ci`, `revert`. Any other type means the commit is **not** a conventional
  commit and is dropped entirely (the parser must be strict here: a bare
  word like `bump` in `bump version numbers` is not a type and the line is
  not a header).
- `scope` (optional) is `[a-z0-9_-]+`.
- `!` immediately before the `(` or immediately before the `:` marks the
  commit as **breaking**.
- `:` must be followed by one or more spaces and a non-empty description; the
  description (trimmed, may contain further colons) becomes the changelog
  entry text.
- **Footer**: if any body line, after stripping surrounding whitespace,
  starts with the exact string `BREAKING CHANGE:`, the commit is also
  **breaking** (a `!` and a footer that both mark breaking simply mean
  breaking once — there is no "double" bump).
- A header that matches none of the forms above (including an empty first
  line) → commit dropped.

## Mapping commits to packages

- **With a scope**: the commit concerns exactly the package whose *name*
  equals the scope; the file list is not consulted. If no package has that
  name, the commit is **dropped entirely**.
- **Without a scope**: the commit concerns every package that matches at
  least one changed file. A file belongs to the package whose `path` prefix
  is a string-prefix of the file path; when several prefixes match (nested
  prefixes), the **longest prefix wins**. Files matching no package are
  ignored. If no file matches any package, the commit is dropped.

A single commit can therefore touch several packages; it is applied to each
of them.

## Semver bump rules (per package, per commit)

| condition            | bump class |
|----------------------|------------|
| breaking (`!` or footer) | **major** (overrides the type's usual class) |
| `feat`               | minor      |
| `fix`                | patch      |
| `refactor`, `perf`, `test`, `style`, `build`, `ci`, `revert` | patch |
| `docs`, `chore`      | none (no bump, and **no changelog entry** is ever written for them) |

**Aggregation / tie ordering**: for each package, the bump class of the
release is the **strongest** class among its commits, with priority
`major > minor > patch > none`. The new version is computed from the current
version by that single strongest class: major → `(X+1).0.0`, minor →
`X.(Y+1).0`, patch → `X.Y.(Z+1)`. Packages whose strongest class is `none`
(including packages with no commits at all) get **no output at all**: not in
`bumps.json`, no changelog directory. Corner case: a breaking `docs`/`chore`
commit bumps major but writes no entry, so its changelog may legally contain
no sections.

## bumps.json (byte format is not graded; structure is)

```json
{
  "<name>": {"from": "<current>", "to": "<new>", "bump": "major|minor|patch"}
}
```
Keys sorted alphabetically by package name, written with `indent=2` plus a
trailing newline.

## CHANGELOG.md (byte-exact canonical format)

```
# <name> Changelog

## [<to>] - <date>

Previous release: <tag>

### Added

- <description> (<first 7 chars of hash>)
```

- `<date>` is verbatim from `--date`; `<tag>` from `last_tag.json`.
- Section titles, in this order, **only if non-empty**: `Added` (feat),
  `Fixed` (fix), `Changed` (refactor, perf, test, style, build, ci, revert).
- Entry lines list the description followed by ` (<hash[:7]>)`.
- Entries are chronological (order of appearance in `commits.jsonl`).
- Exactly one blank line separates every block; the file ends with a single
  trailing newline.

## Your job

1. Write `/app/changelogger.py` implementing the contract above.
2. Produce the visible release outputs:
   ```
   python3 /app/changelogger.py /app/repo_state --date 2025-06-15 --out /app/release
   ```
   (exit 0). The grader re-runs your CLI on the visible state **and on
   hidden repository states you have never seen** — including commits that
   touch several packages at once, unknown scopes, `!`/footer stacking,
   no-bump packages, version tie-breaks and empty commit logs — and
   recomputes `bumps.json`+CHANGELOG bytes itself from the documented rules.
   Byte-exact changelog comparison means whitespace, section order and entry
   text must match the canonical format above exactly. Hardcoded visible
   outputs fail the hidden states.