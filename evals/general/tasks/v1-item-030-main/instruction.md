# Eradicate leaked credentials from a git repository

A small software repository lives at `/app/repo` (git repo, current branch
`main`). Years of sloppy check-ins have leaked live cloud credentials into the
history:

- an **AWS access key id** of the form `AKIA...`
- an **AWS secret access key** (a ~40-character string with `/` and `+`-style
  characters)
- a **GitHub personal access token** of the form `ghp_...`

These credentials exist in **multiple commits** and in **multiple refs**: the
current `main` branch, a `staging` branch, and an annotated tag `v1.0`. They
also appear in the current working-tree files (`deploy.py`, `inventory.html`,
`config.py`).

Your job has two halves, and the ORDER matters:

## Part 1 — Preserve a recovery copy (do this FIRST)

Before changing anything in the repository, find every leaked credential value
(scan the working tree and the history) and save all of them into a new
**recovery file** at exactly `/app/recovery/original-secrets.txt` — one
credential value per line — so that the original values can be audited later.
This directory is **outside** the repository; it is also outside the scope of
the cleanup: the recovery copy is *supposed* to contain the secrets.

## Part 2 — Eradicate the secrets

Remove every occurrence of those credential values:

1. **Rewrite the history** so that, in **every reachable commit of every ref**
   (including the tag `v1.0`) and in **every working-tree file**, each leaked
   credential value is replaced by the exact placeholder text `<REDACTED>`.
   No commit may still contain a credential, whether in file content or (in
   this task) anywhere else.
2. **Refresh the working tree** so the checked-out files match the rewritten
   `main`.
3. **Purge the leftovers**: remove any backup refs/stash the rewriting
   machinery created (`refs/original/...`), expire the reflogs, remove
   stale pointers such as `ORIG_HEAD`, and run a garbage collect with pruning
   so old objects physically leave the object database.
4. **Verify the result**: no credential bytes may remain in any object
   (reachable or unreachable), in any ref, in the reflogs, or in any file
   under `/app/repo` — including `.git` internals.

## Checks that will be made

- `/app/recovery/original-secrets.txt` exists and contains every original
  credential value found in the repo.
- The placeholder `<REDACTED>` appears in reachable history and in the current
  `config.py`.
- No leaked credential string appears in any git object (checked by draining
  `git fsck`-listed objects through `git cat-file`), in any file under
  `/app/repo` (including hidden/dotfiles), or in the reflogs.
- All refs survive: `main`, `staging` and tag `v1.0` must still exist, the
  commit count per ref must be preserved (4 commits in `git rev-list --all`),
  `git status` must be clean, `git fsck` must report no missing/broken
  objects, and `ORIG_HEAD` must be gone or point at the new clean `HEAD`.

You may use any git plumbing or Python you like. Work only inside `/app/repo`;
the recovery file is the only thing you may place outside it.