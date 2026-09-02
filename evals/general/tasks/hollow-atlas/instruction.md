# Hollow Atlas — git lifecycle repair

The "Atlas" release control-plane repo has several git/ops problems. You must fix
them and stand up a bare, SSH-served remote. Everything operates on real git
repositories and real files under `/app`; there is no mocked network.

## Files already present

- `/app/repo` — a git repository, currently checked out on branch **`main`**.
  `main` contains `README.md`, `src/app.py` and `.github/workflows/deploy.yml`.
  - A **hidden stash** (`stash@{0}`, message `lost aurora work`) holds lost,
    off-branch work: a brand-new file `src/recovered_work.py` that belongs on the
    `feature-aurora` branch and is visible *nowhere* on `main`.
  - `main` has **no** `feature-aurora` / `feature-marble` branches yet.
- `/app/bundles/aurora.bundle` — a git bundle carrying the `feature-aurora` branch
  (tip contains `src/aura_mapper.py`).
- `/app/bundles/marble.bundle` — a git bundle carrying the `feature-marble` branch
  (tip contains `src/marble_ledger.py`).
- `/app/ci.yml` — an unsanitized standalone copy of the deploy workflow
  (identical to `/app/repo/.github/workflows/deploy.yml`).

No `git` credentials are configured yet (you may set a local identity as needed).
GNU `openssh-server`, `openssh-client`, `git` and `python3` are installed.

## What to produce

Create/update these deliverables (all real, verifiable artifacts):

1. **`/app/repo`** — working git repository in which:
   - branches **`feature-aurora`** and **`feature-marble`** exist, checked out by
     fetching the bundles in `/app/bundles/` (use the bundle `HEAD`/refs; a bundle
     with only a bare `HEAD` must still yield a local branch). `feature-aurora`
     must contain `src/aura_mapper.py` and `feature-marble` must contain
     `src/marble_ledger.py`.
   - the lost stash is recovered onto `feature-aurora`: `src/recovered_work.py`
     appears (via commit) on `feature-aurora` with exactly the content that the
     stash holds. Unrelated files/branches are untouched.
2. **`/app/deploy/aurora/`** and **`/app/deploy/marble/`** — isolated deployment
   directories. `/app/deploy/aurora` must contain the full `feature-aurora` tree
   (including `src/aura_mapper.py` **and** `src/recovered_work.py`) and must **not**
   contain `src/marble_ledger.py`. `/app/deploy/marble` must contain the full
   `feature-marble` tree (`src/marble_ledger.py`) and must **not** contain
   `src/aura_mapper.py` or `src/recovered_work.py`. Neither branch's content may
   overwrite the other's directory.
3. **`/app/ci.yml`** and **`/app/repo/.github/workflows/deploy.yml`** — sanitized
   workflow files with the external upload sink removed (rule below).
4. **`/app/bin/checkout.py`** — a reusable helper (see contract below).
5. **`/app/bin/sanitize.py`** — a reusable helper (see contract below).
6. A **bare git repository at `/srv/git/atlas.git`** owned by a dedicated OS user
   **`gitops`**, reachable and writable over SSH as
   `gitops@localhost:/srv/git/atlas.git`. `sshd` must be running. A client key pair
   must let passwordless cloning **and pushing** to that URL work (see Contract).

## The upload-sink sanitization rule

A workflow line is a **comment** when, after stripping leading whitespace, its first
character is `#`. **Every non-comment line** must be free of the case-insensitive
token `nightfall-ops.example`. Any non-comment line that contains that token must be
removed **entirely**. Comment lines are preserved verbatim even if they mention the
endpoint. All other lines are preserved byte-for-byte. Apply the same rule to both
`/app/ci.yml` and `/app/repo/.github/workflows/deploy.yml`.

## `/app/bin/checkout.py` contract

```
python3 /app/bin/checkout.py <bundle_dir> <git_repo_dir>
```

For every `*.bundle` under `<bundle_dir>`: inspect the bundle's refs (use
`git bundle list-heads` / `git bundle verify`). For each `refs/heads/...` head,
fetch it into `<git_repo_dir>` creating the matching local branch. If a bundle has
no `refs/heads/*` (only a bare `HEAD`, e.g. a snapshot bundle), create a local
branch named `<bundle-basename-without-.bundle>` pointing at that `HEAD` commit
(this is the HEAD-reference fallback). If `<git_repo_dir>` does not yet exist,
initialize it (`git init -b main`). Print each created branch name, one per line,
to stdout. It must not hardcode branch or fixture names.

## `/app/bin/sanitize.py` contract

```
python3 /app/bin/sanitize.py <in> <out>
```

Read `<in>`, write `<out>` applying the line rule above (drop non-comment lines that
contain `nightfall-ops.example` case-insensitively; keep everything else byte-for-byte).

## SSH remote — contract

- Create a dedicated OS user **`gitops`** (home dir `~gitops`).
- Generate an ed25519 key pair at **`/app/ssh/deploy_key`** (and `.pub`); install the
  **public** key into `/home/gitops/.ssh/authorized_keys` so it enables login.
- Create the bare repo `/srv/git/atlas.git` (`git init --bare`), owned by `gitops`.
- Start `sshd` (e.g. `mkdir -p /run/sshd; /usr/sbin/sshd`) so a client on `localhost`
  can use `ssh -i /app/ssh/deploy_key gitops@localhost` and
  `git clone gitops@localhost:/srv/git/atlas.git`.
- A push to a new branch in that remote must succeed.

Your script must leave `sshd` **running** and everything in place; the verifier will
clone from and push to the remote after you finish.

## Constraints

- Work only in/under `/app` except where this spec explicitly names a system path
  (`/srv/git/atlas.git`, `/home/gitops`, `sshd` config, ssh host keys in `/etc/ssh`).
- Do not modify files under `/tests/`; your solution never reads `/tests`.
- Do not delete the stash, but after your work the stash may remain (you apply, not
  necessarily drop it). The recovered file must be **committed** on `feature-aurora`.
- You may add a git remote (e.g. `origin`) pointing at `/srv/git/atlas.git`.
- Leave no world-writable secret dump; `authorized_keys` and the SSH config should be
  sensible (the test user intentionally relies on your key).