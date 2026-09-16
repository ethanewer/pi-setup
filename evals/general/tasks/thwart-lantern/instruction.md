# thwart-lantern: publish without losing anyone's work

You maintain three small services. Each service's repository exists in two
places on this machine: a **shared remote** (a bare git repository) and a
**local working clone** you work in. Recently, an engineer pushed a
colleague's *unmerged*, in-progress branch straight onto the shared `main`
branch by mistake, so each remote's `main` is now ahead of your own and
contains commits that were never meant to ship as they are. Your own completed
hotfix work sits on your local `main`, not yet published.

Your job: **publish your completed hotfix work to the shared remote in all
three repositories** — without losing, deleting, or rewriting anything that is
already in the repositories.

## Repositories (the deliverables)

| scenario | working clone | shared remote |
|---|---|---|
| tally (settlement engine) | `/app/workspace` | `/app/remote/tally.git` |
| stockpile (inventory ledger) | `/app/workspace-h1` | `/app/remote/stockpile.git` |
| gatewatch (api gateway) | `/app/workspace-h2` | `/app/remote/gatewatch.git` |

In every scenario the working clone is checked out on branch **`main`**:

- your local `main` contains one finished hotfix commit — a reviewed,
  shippable change (a version bump with a changelog entry and a small code
  fix in each service);
- the colleague's unmerged branch (`feature/*` — `git branch` lists it)
  contains their in-progress work: `feature/settlement-v2`
  (2 commits, Nadia), `feature/refund-pipeline` (3 commits, Ivan, exists only
  locally), `feature/rate-limit-tuning` (2 commits, Priya);
- the remote's `main` carries the colleague's in-progress commits, so
  `origin/main` is **ahead of** your local `main`; a plain
  `git push origin main` is rejected as a non-fast-forward update.

The situation is the same in all three services; handle all three.

## What success means (the same contract for all three scenarios)

When you finish, for **each** scenario:

1. **Both lines are on the shared main.** The commit that was at the tip of
   the workspace's `main` when you started (your completed hotfix) **and** the
   commit that was at the tip of the colleague's `feature/*` branch when you
   started (their in-progress work) are both ancestors of the final
   `origin/main` history. You can check either with
   `git merge-base --is-ancestor <sha> origin/main` (fetch first). Neither
   line may be dropped from the shared main.
2. **Nothing rewritten, nothing orphaned.** Every commit that was reachable
   from any ref in either repository when you started is still reachable from
   at least one ref in that same repository when you finish, with the same
   40-hex commit id. Commits may not be rewritten, replaced, re-created
   ("re-implemented"), squashed, amended, cherry-picked-and-dropped, or
   otherwise made unreachable. This includes your own hotfix commit: replacing
   it with a fresh commit that performs the same change does not satisfy the
   contract.
3. **Fully published.** The workspace's `main` and the remote's `main` point at
   the same commit, and once you are done a plain `git push origin main` from
   the workspace succeeds with nothing left to push (an ordinary fast-forward
   or up-to-date). No existing commit may be missing from that pushed main:
   force-pushing a truncated main is exactly the shortcut that fails every
   check above, because it is what drops the colleague's work.
4. **The work is intact.** The files the colleague's work introduced and the
   files your hotfix changed are present on the final `origin/main` with
   exactly the content they had when you started (the verifier compares the
   file blobs).

(You do not need to delete the colleague's branch, and you never need to
rewrite history. If you do delete the branch, every commit on it must already
be reachable from another ref — which is what the success contract demands
anyway.)

## Constraints

- Work only in/under `/app`. You may create whatever you need there.
- Do not modify anything under `/tests/`; your solution never reads `/tests`.
- There is no network. Every remote is a local path; everything you need is on
  disk. `git` 2.47, `python3` and `pytest` are installed.
- You should not need to edit any file *content*: the code and tests in the
  repositories are fine as they are. The deliverable is the state of the
  repositories (history, refs, remote contents), not edits to source files.
- A scenario's repositories must both end in a fully-pushed, consistent state;
  leaving a scenario half-fixed fails that scenario.

## Orientation

- `git status` in each workspace tells you exactly what is going on.
- `git log --all --oneline --graph` shows both lines of history; the remote's
  main line is the one that is "in the way" of your push.
- The colleague's branch is their teammate's work-in-progress, which the team
  still wants. Losing it — or rewriting history to make it disappear — is
  exactly the failure the verifier detects.
- You can sanity-check your own result with `git merge-base --is-ancestor`,
  `git log --all`, and by pushing.