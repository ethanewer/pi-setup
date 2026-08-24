A Git repository at `/app/repo` lost a commit. Someone performed a `git reset --hard` that moved `HEAD` backwards, discarding a commit that had added a file `secret.txt`. That commit is no longer reachable from any branch, tag, or the tip of `HEAD`, but it is still referenced by the repository's **reflog** (the `HEAD@{...}` entries) until those entries expire.

Recover the exact contents of `secret.txt` as committed in that lost commit, and write them (with nothing else) to `/app/recovered.txt`.

You may use any Git plumbing/porcelain commands. The relevant technique: read the reflog (`git reflog --all` / `git reflog`), identify the lost commit, and inspect its tree (e.g. `git show <commit>:secret.txt` or `git cat-file`).

The verifier independently finds the same lost content through the reflog and compares it with `/app/recovered.txt`.