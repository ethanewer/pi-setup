A Git repository at `/app/repo` accidentally has a sensitive file `secret.txt` in its **history**: a commit added it in the middle and it is still present in subsequent commits' trees. You must **rewrite the repository's history** to purge `secret.txt` from every commit.

Requirements after you finish:

- No commit reachable from `HEAD` may contain a tree entry named `secret.txt` (check e.g. with `git ls-tree -r <commit>` for each commit in `git log --all`).
- The legitimate files must still be present at `HEAD`: `readme.md` contains the line `main cfg`, `seed.cfg` contains `seed=1`, and `feature.txt` contains `2.0`. Remove `secret.txt` from the working tree too when you rewrite history.
- The rewrite must preserve a valid linear project history (do not just `git reset --hard` to drop commits wholesale in a way that loses the other files — use a history rewrite such as Git's `git filter-branch` or `git rebase`).

A typical approach: rewrite all commits while removing the path, dropping now-empty commits:

```
cd /app/repo
git filter-branch --force --index-filter \
  'git rm -r --cached --ignore-unmatch secret.txt' --prune-empty -- --all
```

then remove the working-tree copy:

```
git rm -f secret.txt
git commit -m "remove secret from working tree" (only if the tree still contained it)
git gc  (optional)
```

The verifier checks that no reachable commit contains `secret.txt`, that the three legitimate files retain their exact content at `HEAD`, and that the history is still linear/valid.