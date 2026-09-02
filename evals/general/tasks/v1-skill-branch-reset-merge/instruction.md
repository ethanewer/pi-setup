In `/app/workflow` there is a git repository. Inspect it with `git log --oneline --all`
and `git status` before you start. Its history is:

- `main` branch: commits `base` → `add app.py` (HEAD of main).
- `feature` branch (created from `add app.py`): commits `add util module` → `WIP: experiment`
  → `add util tests`. The middle commit, `WIP: experiment`, is a broken experiment: it both
  corrupts `util.py` (adds a junk line `JUNK=1` and changes the function body) and adds junk
  files `experiment.py` and `junk.txt`. It must **not** ship.
- The working tree also contains an uncommitted change: a stray `TODO refactor` line was
  appended to `app.py` by mistake. It must be discarded.

Using git's reset / cherry-pick / merge commands, achieve all of the following:

1. Rewrite the `feature` branch so it contains only the good work: the `add util module`
   commit plus the `add util tests` commit, with the `WIP: experiment` commit removed.
   (Recommended: `git reset --hard` the branch back to `add util module`, then
   `git cherry-pick` the `add util tests` commit — record its hash from `git log` first.)
2. Discard the uncommitted `TODO refactor` modification in the working tree (use
   `git reset --hard` against the current HEAD pointer).
3. Merge `feature` into `main` with a real merge commit:
   `git merge --no-ff feature -m "merge feature into main"`.
4. Leave the repository with a clean worktree (`git status --porcelain` empty).

The final `main` branch must contain `util.py` (with the good `double(n)` implementation
returning `n*2`), `test_util.py`, and `app.py`, and must **not** contain `experiment.py`
or `junk.txt` anywhere in its history.
