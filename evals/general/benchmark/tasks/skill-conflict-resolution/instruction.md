`/app/repo` is a git repository containing a workspace that is currently in the middle of a merge. Two branches each edited the same single-line file `config.txt` in conflicting ways, so the merge is now unresolved: the repo has unmerged paths and conflict markers in `config.txt`.

Resolve the conflict and finish the merge so that:

1. The final committed content of `/app/repo/config.txt` is the single line `resolution=durable` followed by a newline.
2. The merge is **completed** with the resolved file staged and committed (HEAD must be a merge commit; a plain rebase or a hard reset is not acceptable).
3. `git status` reports that the working tree has no unmerged or uncommitted paths.

Use git to inspect the situation before editing. You may run any git commands (status, diff, log, etc.) inside `/app/repo`. After resolution, `git status` should be clean and `git log --merges` should show a merge commit at HEAD.

The verifier independently checks that `config.txt` has the required content, that HEAD is a merge commit (two parents), and that the working tree is clean.