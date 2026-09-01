# Eradicate leaked credentials from a git repository (hard)

A software repository lives at `/app/repo` (git repo, current branch `main`).
Over time, live cloud credentials leaked into it in **multiple places and in
multiple forms**:

- an **AWS access key id** of the form `AKIA...+16 chars`
- an **AWS secret access key** (a ~40-character string containing `/` and `+`
  style characters)
- a **GitHub personal access token** of the form `ghp_...` (36 suffix chars)
- a **GitHub fine-grained token** of the form `github_pat_...`

The credentials appear in **file contents** and also in **commit messages**.
They were committed across several commits and are reachable from **four
refs**: `main`, `staging`, tag `v1.0`, and the branch `legacy/2023`. All
objects have been **packed** into packfiles. Some old commits are still pinned
by **reflog entries** and by `ORIG_HEAD`.

## Required end state (all of it)

1. **Preserve a recovery copy FIRST**: before touching the repository, find
   every leaked credential value and save all of them into
   `/app/recovery/original-secrets.txt`, one credential per line. This
   directory is outside the repo and is *exempt* from the cleanup (it is
   supposed to contain the secrets).
2. **Rewrite history** so that in every reachable commit of **every ref**
   (branches AND tag), every credential is replaced — in **both file contents
   and commit messages** — by the exact placeholder `<REDACTED>`.
3. **Refresh the working tree** to the rewritten `main`.
4. **Purge leftovers**: drop filter/backup refs (`refs/original/...`), expire
   the reflogs, remove `ORIG_HEAD`, and garbage-collect with pruning so the
   old packed objects are physically gone.
5. **Verify absence in all refs and objects**: no credential bytes may remain
   in any git object (reachable or unreachable, packed or loose), in any file
   under `/app/repo` (including `.git`), or in the reflogs.
6. **Keep the repository clean**: `git status` must be empty, `git fsck
   --full` must report no missing/broken objects, all four refs must still
   exist, commit counts must be preserved (5 commits in `git rev-list --all`),
   and `ORIG_HEAD` must be gone or point at the new clean `HEAD`. Do NOT leave
   stray credential-bearing files elsewhere in `/app` (the only permitted
   location for original secrets is the recovery file).

## Note on hygiene

Work inside `/app/repo`. Do not leave the credentials lying around in
ad-hoc files (logs, notes, snippets) anywhere in `/app` other than
`/app/recovery/original-secrets.txt`; the final scan checks `/app` as a whole.