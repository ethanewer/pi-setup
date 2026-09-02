# Recover Lost Git Work and Merge Cleanly

There is a git repository at `/app/repo` on branch `main`. While doing routine
repo maintenance, a colleague accidentally dropped an important commit from the
history with `git reset --hard`. The commit is still in the object database but
dangling (reachable only through the reflog / unreachable-object listing).

## Background

- `main` currently has a few commits, but one commit — the **secret payload
  commit** — was created and then *removed* from `main` via a hard reset. Its
  changes are NOT present anywhere in `main`'s reachable history.
- A separate branch named `server` was started from the same pre-reset point
  and modifies **`payload.conf`** (the same file the dropped secret commit also
  modified) plus adds a `server.lock` file. Branch `server` is still reachable
  and only partially merged into the picture.

Current working-tree state of `/app/repo` (on `main`):

```
payload.conf   -> priority=prod      (main work; conflicts with server's edit)
README.md
audit.log
```

The important artifact that was lost lives inside the dangling commit and can be
recovered because git keeps dangling objects (and an entry in the reflog) until
a cleanup (garbage-collection) discards them.

## Required end state

After you are done, `git` must show the following on `main` (checked as the
current branch, from `/app/repo`):

- `payload/token.dat` exists AND contains **exactly**:
  ```
  TOKEN-X7Y9
  ```
- `server.lock` exists AND contains **exactly**:
  ```
  server.lock=on
  ```
- `payload.conf` exists AND its content contains (on its own lines):
  ```
  priority=prod
  server=mid
  ```
- `audit.log` is present (already there).
- The recovered `payload/token.dat` is **reachable from `main` HEAD** (i.e. it is
  part of the committed tree on the checked-out branch, not just a loose file on
  disk).
- `git status` reports a clean working tree (no staged/unstaged/untracked
  surprises beyond the files above) and `git fsck --full` runs without any
  "broken"/ "missing" errors.
- You SHOULD also run `git gc` (cleanup) — but only AFTER the token and the
  merged state are fully reachable, so cleanup does not destroy them.

## Suggested sequence (exercise these explicitly)

1. **Inspect history before changing anything.** Read `git log --all`,
   `git show`, `git reflog` and list dangling objects (`git fsck --unreachable
   --no-reflogs` / `--lost-found`) to find the dropped commit and the branch tip.
   Confirm ancestry and where HEAD points (the reflog records the reset).
2. **Recover before cleanup.** Bring the lost `payload/token.dat` back into the
   working tree (e.g. `git restore -s <lost-sha> -- payload/token.dat` or
   `git show <lost-sha>:payload/token.dat`), then stage and commit it on `main`.
3. **Merge `server`** into `main`. Expect a conflict on `payload.conf` — resolve
   it so the file ends with both required lines in the order shown above.
4. **Verify ancestry and working-tree state.** Use `git status`, `git log`,
   `git fsck` to confirm commit ancestry and that the files are committed.
5. **Clean up** only after recovery: run `git gc` (prune) and confirm the token
   file is still checked out and reachable.

Do all work inside `/app/repo`. There is no separate remote; correctness is
determined only from the local repository and working tree.