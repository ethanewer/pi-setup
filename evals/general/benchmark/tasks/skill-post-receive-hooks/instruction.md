# Git post-receive hook

Create a **bare Git repository** at `/app/repo.git` and install a Git **`post-receive` hook** in it.

Requirements:

1. `/app/repo.git` must be a valid **bare** repository (no working tree), e.g. created with `git init --bare /app/repo.git`.
2. Inside it, the hook file `/app/repo.git/hooks/post-receive` must exist and be **executable** (a shebang script).
3. The hook must run whenever the repository receives a pushed ref, and it must **append a line** to `/app/hook.log`. That appended line must contain the literal text `push_received` and also the pushed ref name (the third argument git passes to post-receive hooks, like `refs/heads/master`).

A simple hook body is:

```bash
#!/bin/bash
while read -r old_value new_value refname; do
  echo "push_received $refname" >> /app/hook.log
done
```

(post-receive hooks read updated refs from stdin, one line per ref in the form `old-value new-value refname`; extract the third field as the ref name.)

The verifier will then perform a real local push of a commit into `/app/repo.git` (from a scratch clone) and confirm that after the push:

- `/app/hook.log` exists and its last line contains `push_received`,
- that line contains a ref name such as `refs/heads/master`,
- and the repository still reports itself as bare.

No network is involved; everything is local.