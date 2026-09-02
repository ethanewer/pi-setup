# Fred Hearth — Repo-Serving Layer

You operate the "Fred Hearth" research group's repository-serving layer. There are
three pieces of work that **all** must be finished and correctly wired together.
Everything is checked at the end, including behavior on inputs you have not seen.

**Do not modify** anything under `/app/papers` (it is your input fixture) and **do
not remove** the `main` branch / commit history of `/app/repo.git`.

## Deliverables

| Path | What it is |
|------|-----------|
| `/app/repo.git/hooks/post-receive` | executable git hook that deploys pushed branches into the served tree |
| `/app/deployed/...` | the served directory: one top-level entry per branch (its full tree) |
| `/app/normalize_url.py` | URL normalizer program (runnable from CLI, one canonical per line) |
| `/app/urls.tsv` | tab-separated file: one canonical repository URL per line |
| `/app/paper_links.json` | JSON-lines mapping of every paper id -> its official repo URL |

---

## Part 1 — Git receive-hook deployment

`/app` already contains a **bare** repository at `/app/repo.git` with a single
branch `main` (tree: `README.md`, `index.html`, `assets/site.css`, subdirs as
committed).

Write an **executable** hook at `/app/repo.git/hooks/post-receive` so that, whenever
a push targets this bare repo, each branch lands in the served directory under its
own path:

```
/app/deployed/<branch>/          <- full tree of branch <branch>
```

Exactly, when the hook receives the ref `refs/heads/B` on stdin:

1. `/app/deployed/B/` becomes a **mirror** of branch B's complete tree — same files,
   same relative paths, byte-identical file contents. Multi-level branch names such
   as `docs/guides/feature` become nested served directories:
   `/app/deployed/docs/guides/feature/`.
2. When an already-deployed branch is updated with a new commit, the served content
   is **replaced** so it again equals the newest tree (stale files removed, changed
   files updated). The mirror must never hold leftover content from earlier commits.
3. When a branch ref is **deleted** (`(delete)` on that ref), its served directory
   `/app/deployed/B/` is **removed**.
4. Refs that are **not** branch refs — e.g. `refs/tags/...` — are ignored: they must
   create **no** deployment entry and must **never abort** the push.
5. The hook must **never write outside `/app/deployed`** (no `..` escapes, no writes
   into `/app`, nowhere else), and must not leave empty/partial dirs behind when a
   tree is replaced or removed.

You must also deploy `main` yourself before finishing so that `/app/deployed/main/`
already mirrors the `main` tree (apply the same logic the hook uses — e.g. run the
hook's deploy step for that ref).

You may implement the hook however you like (`git archive | tar`, a detached
worktree, `git checkout` against a temp work-tree, ...). The observable contract
above is what will be tested, including pushing live hidden branches.

Constraints:
- The hook is run by git on push; its stdin is lines `<old> <new> <ref>`. Derive the
  repo location robustly (use `GIT_DIR` or hardcode `/app/repo.git`); never depend
  on the current working directory.
- It must work whether `/app/deployed` already has entries or is empty.
- Handle each branch ref on the input independently; a single push may carry several
  refs of mixed kinds.

---

## Part 2 — URL normalization

Write `/app/normalize_url.py` — a program/importable module that computes the
canonical form ℭ of repository URLs. It must be runnable from the CLI and also
importable as a module. Match this spec exactly; the hidden checks compare your
output against an independent implementation.

### CLI contract

- `python3 /app/normalize_url.py FILE [FILE ...]` — prints one output line per input
  line, in order.
- `python3 /app/normalize_url.py < FILE` (no file args) — same, reads stdin.
- Exit code 0 for normal runs.

### Canonical form ℭ

Strip leading/trailing ASCII whitespace from each line, then:

1. **Blank** line → blank output line.
2. Contains **no** `://` (no explicit scheme — malformed/non-absolute) → output the
   line with whitespace stripped, **unchanged** (pass-through).
3. Otherwise: lowercase the **scheme** and the **host**; drop a **default port** for
   that scheme (`http:80`, `https:443`, `ftp:21`) but keep any non-default port and
   any embedded userinfo (`user:pass@`); strip **all** trailing `/` from the **path**
   (path `/` becomes empty); sort **query** parameters stably by key (equal keys keep
   relative order) and drop the `?` entirely if there are no params; drop the
   **fragment**. Re-assemble as `scheme://host[:port]/path[?query]` (no fragment).

Examples:

```
hello?none:42                        -> (passthrough line)
https://example.com/hat/            -> https://example.com/hat
https://example.com/hat?b=2&a=1     -> https://example.com/hat?a=1&b=2
HTTP://Example.COM/A/?a=9&x=1       -> http://example.com/A?a=1&x=9
https://example.com:443/secure      -> https://example.com/secure
http://example.com:80/x             -> http://example.com/x
   https://x.io/n/?p=1              -> https://x.io/n?p=1
                                    -> (blank line)
```

ℭ must be **idempotent**: `ℭ(ℭ(x)) == ℭ(x)`. The hidden inputs mix normal URL
variants, trailing-slash/query-order variants, default-port variants, fragments,
blank lines, and malformed (no-scheme) lines.

---

## Part 3 — Paper → official-repo catalogue

Under `/app/papers/` (input fixture, read-only for you) there is a catalogue:

- `/app/papers/index.html` — a table; each paper row has a `data-pid` id attribute
  and a `detail` anchor linking to `<id>.html`.
- `/app/papers/<id>.html` — one detail page per paper (not all listed papers have a
  page). A detail page contains:
  - `<article id="<id>">`,
  - an optional `<div class="affiliation">…</div>` (the paper's affiliation org
    label; may be empty/absent),
  - `<ul class="repos">` with `<a class="repo" href="…">` candidate code locations.
    Exactly one of them is the paper's **official, author-maintained repository** on
    GitHub (owner == affiliation). The rest are reworks/mirrors/on other hosts.

**Official-repo rule.** A candidate is the official repo iff its `href` is a GitHub
repo `https://github.com/Owner/repo` where `Owner` (the path segment right after
`github.com/`) **equals** the page's `affiliation` text exactly (case-sensitive).
There is at most one such candidate. Edge cases:

- a draft paper listed in the index but with **no detail page** → unresolvable;
- a paper whose page affiliation is **empty** → unresolvable;
- a paper with no GitHub candidate owned by the affiliation → unresolvable.

### Outputs

`/app/paper_links.json` — **JSON-lines**: one JSON object per line, every paper in
the index, in any order:

```json
{"id": "fh-1", "url": "https://github.com/Arcadium/sidelobe"}
```

- `url` = the **canonical form ℭ** (from Part 2) of the official repo URL, or `""`
  when unresolvable.
- The id set must equal the index's paper id set: no missing, no extra, no dupes.

`/app/urls.tsv` — one **canonical** official repository URL per line, one line per
resolved paper only (unresolvable papers are omitted). No duplicates. Each line must
already be canonical (normalizing it again leaves it unchanged).

The checker independently re-derives the mapping from `/app/papers` and compares it
to both files byte-for-byte (URL-for-URL, id-list equality).