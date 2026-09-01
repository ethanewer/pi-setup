A git repository exists at `/app/repo`. Its history was rewritten: a local branch that once contained a file named `secret.txt` was **force-deleted**. Because its commits are no longer reachable from any branch or tag, they are now **dangling** (unreachable) objects — but they may still be present in the object store and recoverable via the reflog or `git fsck`.

Recover the **contents of `secret.txt`** from the repository's dangling history and write exactly that content to `/app/recovered.txt`.

Requirements:
- `/app/recovered.txt` must contain only the file's text (as committed on the deleted branch) with no added explanation.
- You may use any git plumbing/porcelain commands (`git fsck --unreachable`, `git fsck --lost-found`, `git reflog`, `git show`, `git cat-file`, etc.).

The verifier independently locates the same dangling content in `/app/repo` and compares it to `/app/recovered.txt`.