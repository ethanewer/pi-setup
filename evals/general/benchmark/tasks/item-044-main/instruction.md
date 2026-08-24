# Reconstruct the correct ARC-AGI task repository from a Git bundle

`/app/arc-repo.bundle` is a **Git bundle** containing a small repository of
ARC-AGI task files (JSON). The repository was bundled with several branches;
one of them holds a legitimate bug fix that must be incorporated into `main`,
another holds changes that **must not** be merged, and a third holds a
**malformed** task file that must never enter the tree.

Your job: follow the precise repository-state recipe below — clone from the
bundle, **inspect the refs** before touching anything, apply **only** the
legit fix, and leave `/app/arc-repo` in the exact final state described here.

## ARC-AGI data format (reference)

Each task file is JSON with two keys: `"train"` (examples) and `"test"`
(examples). Each example has `"input"` and `"output"` keys whose values are
**rectangular** grids: a list of rows, each row a list of integers 0..9, all
rows of equal length. Valid files only.

## Step 1 — create the working repository (bundle only, no network)

```
git clone /app/arc-repo.bundle /app/arc-repo
cd /app/arc-repo
```

There is no remote and no network access; the bundle is the only transport
(canonical for offline delivery). It is a valid bundle (`git bundle verify`).

## Step 2 — inspect the refs before merging

Run `git show-ref` / `git branch -r` (then `git log --oneline --all` and
`git show --stat <sha>` for the interesting commits). The bundle contains
three heads:

- `main` — the original commit. Contains three task files:
  `tasks/byou6dgf.json`, `tasks/1e0a9b12.json`, `tasks/3ccc3b22.json`.
  **`tasks/1e0a9b12.json` has a bug**: the transformation rule for this task
  is "rotate the grid 90° clockwise", but two of its outputs are wrong
  (a typed-in cell swap in `train[1].output` that does not match the rule).
- `feature/fix` — two commits on top of main:
  1. `fix: correct rotate outputs in 1e0a9b12` — the **legitimate** change.
  2. `chore: drop 3ccc3b22 and annotate byou6dgf` — **unwanted**: it deletes
     `tasks/3ccc3b22.json` and overwrites `tasks/byou6dgf.json` with an
     annotation-only stub.
- `wip/corrupt` — adds `tasks/9e9ff3c4.json`, which is **malformed**
  (a grid with rows of unequal length — violates the ARC format). It must
  not be merged and its file must not appear anywhere in the final tree.

## Step 3 — merge ONLY the legitimate fix

Apply the `fix commit`'s changes to `main` without importing the `chore`
commit. Any of these is acceptable: `git cherry-pick -n` (stage; then commit),
`git cherry-pick`, or reconstructing the file from `git show` of that commit.
For `cherry-pick -n` + commit the message `fix: ...` is fine; the result on
disk is what matters.

Verify with `git diff origin/main` (or `origin/main...HEAD`) that the only
difference is `tasks/1e0a9b12.json`, and check `git status` is clean.

## Step 4 — verify the final state

- You are on branch `main`; working tree clean.
- `tasks/1e0a9b12.json` is exactly the fixed file (below).
- `tasks/byou6dgf.json` and `tasks/3ccc3b22.json` are exactly their original
  contents from `main`.
- `tasks/9e9ff3c4.json` does **not** exist.
- Every remaining task file satisfies the ARC JSON format (rectangular
  grids).
- The rotation rule now holds for every example in `1e0a9b12.json`.

### Correct content of `tasks/1e0a9b12.json` (the goal)

```json
{
  "train": [
    {"input": [[1, 2], [3, 4]], "output": [[3, 1], [4, 2]]},
    {"input": [[5, 6], [7, 8]], "output": [[7, 5], [8, 6]]}
  ],
  "test": [
    {"input": [[9, 1], [2, 3]], "output": [[2, 9], [3, 1]]}
  ]
}
```

## Artifacts to leave in /app

- `/app/arc-repo` — the repository in the final state above;
- the original `/app/arc-repo.bundle` untouched.

Leave a note of which commit hash you applied (e.g. in `/app/NOTES.md`) —
the verifier checks the repository state, not the note.