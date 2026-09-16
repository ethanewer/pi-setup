# bracket-quay: repair a documentation-generator regression

## What you are handed

`/app/quayside` is a Python monorepo for **quaydoc**, a self-contained
documentation site generator (a parser, renderer, template engine, theme, dev
server, link checker, and CLI for a small markup language). It is written in
pure standard-library Python 3.12 — no third-party runtime dependencies — and
it is a real Git repository with more than thirty commits of history included.
Run `cd /app/quayside && git log --oneline` to see it.

The project's own pytest suite lives in `/app/quayside/tests` (100+ tests) and
is **green right now** — run `cd /app/quayside && python3 -m pytest -q tests`
to confirm. The suite stayed green while the bug below was shipped, so it does
not cover the failure; do not rely on it alone, and do not weaken or delete
tests to make anything pass.

Useful orientation:

- `python3 -m quaydoc.cli build <docs-root> -o <out>` builds a site,
- `python3 -m quaydoc.cli check <out>` runs the built-in link-integrity
  checker against a built site,
- `/app/quayside/README.md` and `/app/quayside/docs/guide/` explain the
  markup and the commands.

## The report (user-facing symptom)

A user filed this during the 0.9.x release cycle, after upgrading from the
previous release:

> Several sections of our published docs are unreachable from links. The
> **table of contents** jump-links and the `[[ ... ]]` cross-references on a
> page work for most headings, but for headings whose titles contain an
> ampersand (`&`) or a colon (`:`) they land nowhere: clicking the link moves
> the URL bar to a `#` fragment, the page never scrolls, and manual links to
> those sections 404. For example, a heading rendered with
> `id="setup-and-first-steps"` while the generated links to that section point
> at `#setup-first-steps`. Plain headings are fine. Everything else renders
> normally, and the same page worked in the previous release.

The maintainers' own triage confirms this is an **application bug introduced
somewhere after the previous release** — not a docs authoring mistake, not a
browser issue, and not something any per-module unit test covers in isolation.
It only shows up when a page is actually rendered.

Your job:

1. **Reproduce** the reported behaviour with quaydoc itself (write a small
   docset that contains headings and cross-references of the kind described,
   build it, and run `quaydoc check` on the output).
2. **Find and fix the underlying cause in the code.** Fix the regression
   itself — do not paper over it in example docs, do not add HTML workarounds
   in prose, and do not weaken the verifier-relevant behaviour (the shipped
   suite will be re-run, and the same class of headings will be exercised from
   angles you have not seen).
3. **Confirm** the fix: rebuild your reproduction, run `quaydoc check` (it
   must report no broken fragments), and keep the shipped test suite green
   (`python3 -m pytest -q tests` from `/app/quayside`).
4. **Diagnose the history.** Using the repository's Git history, identify the
   exact commit that introduced the regression. You are expected to consult
   `git log`, `git blame`, `git log -S "..."` or similar while working — the
   answer is derivable from the repository you were handed, deterministically.
5. **Write the postmortem.**

## Deliverables

- **`/app/quayside`** — the repository, with the fix applied in the working
  tree (and committed if you like). It must remain a Git repository containing
  the full history you were given; do not rebase, squash, rewrite, or delete
  history, and keep every existing module and test file in place.
- **`/app/postmortem.md`** — a postmortem in plain UTF-8 Markdown. It must
  contain a line formatted exactly as

  ```
  Introduced by commit <40-character lowercase hex sha>
  ```

  naming the commit that introduced the regression. The line must be its own
  line and contain nothing else. Explain the root cause and your fix in the
  rest of the file (free-form). The 40-hex sha must be the **introducing**
  commit in the repository's history — not your fix commit, and not the commit
  the bug was discovered in — and the verifier checks it against the history
  directly.

Both deliverables live at the exact paths above. Nothing outside
`/app/quayside` and `/app/postmortem.md` is evaluated, but the container you
work in is disposable — create scratch docsets anywhere under `/tmp`.

## Constraints

- Python 3.12 only. Do not add any third-party dependency; the project is
  stdlib-only by design, and the verifier has no network to install anything.
- Do not modify anything under `/tests` or `/solution` (they are not writable
  from your session anyway).
- The verifier re-runs the shipped test suite and runs its own additional
  checks against your repaired tree, so make the fix robust, not cosmetic.