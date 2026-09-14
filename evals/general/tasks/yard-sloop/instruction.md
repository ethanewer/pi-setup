# yard-sloop: Semgrep drops the `_git` segment from Azure DevOps repository links

## Situation

`/app/src` is a shallow, pinned clone of the Semgrep project
(`https://github.com/semgrep/semgrep`), checked out at a specific upstream
commit, and installed from that tree in editable (development) mode, so the
code you `import` is exactly the checked-out Python source. Python 3.12 and
pytest are installed. Everything you need is on disk; the network is
unavailable during the trial and the verifier rejects trees that pulled in
upstream objects, so do not fetch, clone, or install anything.

Semgrep attaches clickable links to its findings: when you run a scan in a
repository, each finding records the project URL on the code-hosting platform,
derived from the repository's remote. This task is about what Semgrep does to
one family of those remotes.

## The bug (as a user would report it)

> "The links Semgrep puts on my findings point at a page that does not exist.
> My repository on Azure DevOps lives at
> `https://dev.azure.com/test/TestName/_git/Core.Thing` — the real project
> page — but the URL Semgrep reports for it is
> `https://dev.azure.com/test/TestName/Core.Thing`, without the `_git`
> segment. That page is a 404. Semgrep should keep the `_git` segment in the
> URL."

The input Semgrep starts from commonly looks like
`https://test@dev.azure.com/test/TestName/_git/Core.Thing` (an Azure DevOps
remote, possibly configured through the `SEMGREP_REPO_URL` environment
variable or discovered from `git remote`). When Semgrep normalises such a
remote into the clickable project URL, the `_git` segment is silently
dropped. The required behaviour:

- the final project URL keeps the `_git` segment:
  `https://test@dev.azure.com/test/TestName/_git/Core.Thing` must become
  `https://dev.azure.com/test/TestName/_git/Core.Thing`;
- the repository **name** derived from the remote must *not* include the
  `_git` segment (the project/repository name reported for that remote stays
  `TestName/Core.Thing`);
- remotes that do *not* contain a `_git` segment (GitHub, GitLab, plain
  `https://...repo.git`, `ssh://...`, scp-like `git@host:path`) must keep
  producing exactly the URLs they produced before — no stray `/_git` may
  appear in them, and the normal `.git` suffix stripping and
  `ssh`-to-`https` normalisation must be unchanged.

## Your first deliverable: a reproduction, written before any fix

Write `/app/reproduce.py` — a small script that demonstrates the bug by
computing what Semgrep actually produces for the Azure DevOps remote above,
using the installed project code (import it the same way the project itself
does). The file must obey this exact contract, which the verifier enforces:

- When run with `python3 /app/reproduce.py`, it computes Semgrep's
  normalised URL for the remote `https://test@dev.azure.com/test/TestName/_git/Core.Thing`
  and prints exactly one line `url=<result>` where `<result>` is the URL the
  installed code actually produced.
- It exits with status **0** if and only if `<result>` equals the correct
  URL `https://dev.azure.com/test/TestName/_git/Core.Thing`; otherwise it
  exits with a nonzero status.

So on the tree as you find it (bug present) your reproduction must exit
nonzero and print the buggy URL; once the tree is repaired it must exit 0
and print the correct URL. Write it first, run it, and keep it as evidence
that the failure you saw was real.

Deliverable: the file `/app/reproduce.py` (this is what the verifier
executes).

## Then fix the bug

The fix is a code change in the checked-out tree at `/app/src`, in
whatever place is responsible for rebuilding the remote into the clickable
project URL. Do not rewrite history, add remotes, or create new files inside
the repository. Keep every other behaviour the project has documented above
intact.

One thing to be aware of: the project's own automated regression test for
this behaviour happens to be tracked in the tree at the commit you are on,
and — because it was written before the bug was recognised — it asserts the
**old, buggy** expectation (it encodes that the `_git` segment is dropped).
A complete repair brings that tracked test in line with the corrected
behaviour, exactly as the project maintainers did, so the project's own test
suite is green after your change. The verifier runs that test suite from
your tree, so reconcile the stale expectation as part of your work. Drive
your work with the project's own test runner (pytest); the test module that
covers this behaviour is the one that imports the metadata module that
builds these URLs — search the test tree for Azure if you need to locate it.

## Constraints

- Network is unavailable; everything needed is installed already.
- `/opt/golden` (an authoritative copy of fixed-era regression tests),
  `/opt/pristine` (an untouched copy of the tree as you received it), and
  everything under `/tests` and `/solution` are harness-owned. Do not read
  them for your answer and do not modify them.
- The verifier checks that the tree is still at the pinned commit, that no
  files beyond the minimal repair surface were modified, and that the
  upstream fix was not fetched.

## What the verifier checks

1. Your reproduction runs in two contexts: against an untouched pre-fix copy
   of the tree it must exit nonzero and print the buggy URL; against your
   repaired tree it must exit 0 and print the correct URL. Both results must
   match an independent control computation in the same context.
2. The project's own regression test for this behaviour passes, both run
   from your tree and from an authoritative fixed-era copy in the image.
3. The whole package still compiles and imports cleanly.
4. Hidden cases over inputs the upstream regression test does not use pass:
   a no-user Azure URL containing `%20`, an Azure URL ending in `.git`, a
   deep multi-segment Azure owner, `user:pass`-style auth with a dotted
   repository name, a trailing-slash Azure URL, and non-Azure remotes
   (GitHub, GitLab, `ssh://`, scp-like) that must remain untouched.
5. Tree provenance: pinned commit, no fetched fix, only the minimal files
   changed.

Deliverables: the repaired `/app/src` tree and the reproduction
`/app/reproduce.py`.