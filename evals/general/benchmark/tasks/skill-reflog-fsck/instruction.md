# Recovering a "lost" commit with git reflog / fsck

`/app/repo` is a Git repository. It contains a `stable.txt` file (already committed as
`stable base`). Earlier there was also a second commit on the same branch whose commit
subject is `golden-secret` (it added `secret.txt` containing `recover payload: FLAG-48213`).
That branch tip was rewound with `git reset --hard`, so the branch no longer points at
that commit. The commit object still exists but is no longer reachable from any branch.

Your task: discover the full 40-character SHA-1 of that `golden-secret` commit and write
it (with a trailing newline) to `/app/agent.txt`.

Use Git's object-recovery features, for example:

- `git fsck --lost-found` — detects dangling commits and copies them under
  `.git/lost-found/commit/`;
- `git fsck --unreachable` — lists unreachable objects including the dangling commit;
- `git reflog` — shows where refs (and SHAs) pointed, which still lists the lost tip.

Confirm a candidate is correct by checking its subject:

```
git show -s --format=%s <sha>     # must print golden-secret
```

The verifier independently locates the dangling `golden-secret` commit and requires the
contents of `/app/agent.txt` to equal that SHA.