# Umber Yonder — Git forensic secret removal & recovery

You are auditing an incident repository for the small publisher **Paloma
Studio**. A short-lived API key was committed, and a one-off retry credential
was committed and then hastily deleted. Both are still recoverable from git
history and from dangling objects. Your job:

1. **Clone** the incident repo over password-authenticated SSH into `/app/repo`
   (you must automate the interactive password prompt — no approval is
   possible).
2. **Recover** the deleted retry credential and write it to `/app/recovered.txt`.
3. **Expunge** both secrets from the working tree, every reachable commit /
   blob / tree, every commit **message**, and every dangling / reflog object,
   then prune so a byte-level scan of **every object** in the repository finds
   no trace of either secret.
4. **Preserve** every unrelated tracked file **byte-for-byte** — edit only the
   files that actually contain a secret.
5. **Record** the rewritten history and the exact push-and-deploy-trigger
   command list.

Tooling already installed: `git`, `sshpass`, `openssh-client`, `openssh-server`
(already running), `python3`. Work only under `/app`. Do **not** modify the
served remote at `/srv/git/paloma.git`. Do **not** read `/tests` (it is hidden
and irrelevant to you).

---

## The remote and the clone

The incident repository is served over SSH on loopback as:

```
gitdev@127.0.0.1:/srv/git/paloma.git
```

The `gitdev` account's password is **`eastbank4`**. The SSH daemon is already
running and accepts password authentication on `127.0.0.1`. Because the host key
is unknown and the prompt is interactive, clone with something like:

```bash
export GIT_SSH_COMMAND="sshpass -p eastbank4 ssh \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no"
git clone gitdev@127.0.0.1:/srv/git/paloma.git /app/repo
```

`/app/repo` must be a full working checkout of `main` that you obtained by this
SSH clone (its `main` history is what you sanitize).

---

## The two secrets

**Leaked API key** — a literal matching the form

```
[A-Z]{2,6}-[A-F0-9]{4}-[A-F0-9]{4}
```

It is present in a tracked config file in the working tree, in older reachable
commits, and it was also pasted into a commit **message**. Every occurrence must
be purged.

**Retry credential** — a literal matching the form

```
[A-Z]{2,5}:[0-9a-f]{8}
```

It was committed and then deleted from the tree, so it survives **only** in a
superseded or dangling object (an orphaned blob/commit reachable only through
history or reflog). The **recovered credential** is defined as: the credential-
shaped value that exists in the object store but **not** in the current working
tree. If several such values exist, take the lexicographically smallest.
Recover that value and write it to `/app/recovered.txt`.

> A credential-shaped string that still lives in a tracked working-tree file is
> **not** the recovered credential and must be left untouched (it is ordinary
> content, not a leak to chase).

---

## Deliverables (all under `/app`)

| Path | What it must be |
|------|-----------------|
| `/app/repo` | The SSH clone, sanitized (see below). |
| `/app/recovered.txt` | The recovered retry-credential value, one line, nothing else (no trailing whitespace beyond the newline). |
| `/app/rebased_history` | The full rewritten `main` history, one commit sha per line, oldest first (same as `git -C /app/repo log --format=%H --reverse main`). |
| `/app/push_commands.sh` | Executable script; when run it prints the exact push + deploy-trigger command list for the sanitized tree. |
| `/app/repurge.py` | A **reusable** scrubber (contract below), executable. |

All five are verified. The first four are produced for this incident; the fifth
must generalize to any similar repository.

### Placeholder mapping

When you replace a secret inside a file or commit message (case-insensitively):

- leaked **API key** → replace with **`[REDACTED_API_KEY]`**
- **retry credential** → replace with **`[REDACTED_CREDENTIAL]`**

Use the placeholder of the type that matched. Replace only actual secret
values — never rewrite unrelated literal content in the rest of the file.

---

## Sanitization requirements for `/app/repo`

- No reachable or dangling object (blob, tree, commit) and no commit message may
  contain either secret value, **case-insensitively**.
- After rewriting history you must **drop** the filter/superseded refs, **expire
  the reflogs**, and run `git gc --prune=now`, otherwise the old, secret-bearing
  objects remain dangling and fail the scan.
- **Byte preservation:** every tracked file that does not contain a secret must
  be byte-for-byte identical to its original version. Only files that contained
  a secret may change (to the placeholder form).
- `/app/repo` must still be a valid git repository on `main`, with the leaker
  commit messages scrubbed and no residual secret anywhere.

---

## The reusable scrubber `/app/repurge.py`

CLI: `python3 /app/repurge.py <repodir> [out.json]`

It operates **in place** on a linked working git repository and must:

1. **Discover** every leaked-API-key literal (the `[A-Z]{2,6}-...` form) across
   all objects and the working tree.
2. **Recover** the retry credential via the definition above (in objects, not in
   the working tree).
3. **Rewrite** all reachable history (trees, blobs, commit messages) replacing
   the discovered values with the matching placeholder, editing **only** files
   that contain a secret.
4. **Cleanup:** remove original/dangling refs and stale remote-tracking refs,
   expire all reflogs, then `git gc --prune=now`.
5. **Self-verify:** scan every object **and** the working tree, case-
   insensitively, for the discovered values; set `ok` accordingly.
6. Write a JSON result `{"ok": bool, "recovered": <value|null>, "secrets_removed":
   <n>, "head": "<sha>"}` to stdout and to `out.json`. Recovered is `null` when
   there is no recoverable credential.

Handle these **edge cases** (hidden evaluation probes them):

- a secret that appears **only in a dangling object** (working tree and reachable
  history are already clean) — purge the dangling object so the scan passes;
- a secret spread across **multiple files**, and the **same** secret with
  **different casing** inside a commit message;
- a **benign credential-shaped string** in a tracked working-tree file that must
  be preserved byte-for-byte (it is not the recovered credential, and not a leak
  to purge);
- a repository with **no** retry credential (recover `null`, still succeed);
- a path that is **not a git repository**: exit `0` with `{"ok": false}` and do
  not crash.

---

## `/app/push_commands.sh`

An executable Bash script. Running `bash /app/push_commands.sh` prints the exact
commands that would deploy the sanitized site:

- a `git push` to `gitdev@127.0.0.1:/srv/git/paloma.git` of `main:main`,
- a deploy-trigger request to `https://deploy.paloma.example/hook/<short-sha>`
  carrying the placeholder token `[REDACTED_API_KEY]` (never the real key).

Its output must contain the remote URL, a `git push`, the current 12-character
short sha of `/app/repo` `main`, and the placeholder `[REDACTED_API_KEY]`, and
must not contain either secret value.

---

## Success

You are done when: `/app/repo` is the sanitized clone with zero trace of either
secret and all unrelated files byte-identical; `/app/recovered.txt` holds the
correct recovered credential; `/app/rebased_history` matches the rewritten
`main`; `bash /app/push_commands.sh` prints the exact deploy command list; and
`/app/repurge.py` repairs the hidden incident repositories and a non-repository
input without crashing. The remote and `/tests` are never touched.
