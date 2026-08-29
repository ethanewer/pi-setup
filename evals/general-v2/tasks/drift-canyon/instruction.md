# drift-canyon — self-hosted git + profile stack reconstruction

A small developer, Marlow Bayne, keeps a personal profile website and
self-hosts it over git+SSH. Their repo got scrambled: a draft was stashed and
"lost", two bundles were never checked out, and a build script lost its
executable bit. Your job is to write **one** self-contained reconstruction
script that repairs the whole stack.

## Deliverables (both under `/app`)

1. **`/app/solve.py`** — an executable (`chmod +x`) Python 3 program.
   - Running `python3 /app/solve.py` (no arguments) must reconstruct the whole
     stack described below and write the report deliverable.
   - It must ALSO implement a repair subcommand,
     `python3 /app/solve.py repair --home DIR` (details at the end).
   - Re-running it must be safe (idempotent) from any state.
2. **`/app/answer.json`** — a JSON report that `/app/solve.py` writes (see the
   Report section for the exact keys the grader reads).

Put nothing else under `/app` that was not exercise of the task (the image is
delivered to you already seeded; the program you author produces the final
state). Do not read anything under `/tests`.

## Fixtures already on the container (under `/app`)

- `notes/bio.md` — first line is the name (`Marlow Bayne`), then a bio that
  mentions the field phrase "barnacle recruitment".
- `notes/posts/ember.md` — post titled "Into the Ember Mud".
- `notes/posts/harbor.md` — post titled "Harbor at Low Water".
- `notes/pubs.md` — publications; the second contains "Intertidal Letters".
- `site/` — an existing git repository. Default branch is **`main`**. It
  contains copies of the raw notes and `site/deploy/reconstruct.sh`
  (a complete legacy rebuild script that is currently **non-executable** and
  whose bytes are NOT to change).
- `bundles/on-guide.bundle` and `bundles/fieldnotes.bundle`.
- `personal-plan.txt` and `listing.txt` — informational; do not modify either.

Some work exists in the repo's history but is **not present on `main`**: a file
`writing/sketches/story-notes.txt`. It is recoverable (e.g. a stash entry, or
on a different branch) and must be restored.

## Required outcome

### 1. Assemble the profile site into `/app/site`
Create `index.html`, `about.html`, `blog.html`, `publications.html`, and one
`blog/<slug>.html` per post. Contents must satisfy:

- `index.html` contains the name from notes/bio.md ("Marlow Bayne").
- `about.html` contains the bio text, including "barnacle recruitment".
- `blog.html` lists the titles of both posts ("Into the Ember Mud" and
  "Harbor at Low Water").
- `blog/into-the-ember-mud.html` and `blog/harbor-at-low-water.html` exist.
- `publications.html` contains "Intertidal Letters".

### 2. Restore the lost draft and commit it on `main`
The file `writing/sketches/story-notes.txt` (under repo `/app/site`)
must end up with the exact bytes it carried in git history. The content is a
short camping/coastal note that contains the phrase **"the cove lantern"**.
It must not simply be dropped in the working tree — it must be committed to and
tracked on `main` (so `git -C /app/site ls-files` lists it).

### 3. Check out the two bundle branches via HEAD
- `on-guide` — tip from `bundles/on-guide.bundle`
- `fieldnotes` — tip from `bundles/fieldnotes.bundle`

Import each bundle's objects into `/app/site`; resolve each bundle's **the**
tip by its HEAD reference (inspect the bundle's advertised refs if HEAD is not
flat); create a local branch at that tip. Do not assume a bundle's advertised
ref is a flat name equal to your target branch name.

### 4. Serve the repo over a password-authenticated SSH server
- A **bare** repository at `/srv/git/marlow.git` populated with `main` plus the
  local `on-guide` and `fieldnotes` branches (all three must be referenceble).
- Owned by a dedicated OS user **`gitdev`** (create with home `-m` and a
  login shell if it doesn't exist), password **`lantern-9`**.
- sshd running on localhost with password authentication enabled; `gitdev` must
  be able to **clone** and **push** back over SSH to
  `gitdev@127.0.0.1:/srv/git/marlow.git` using only that password (no SSH key).

### 5. Executable build script, unchanged listing
Set the executable bit on `/app/site/deploy/reconstruct.sh` (do not change its
content or its path). Leave `/app/listing.txt` **byte-for-byte** as provided.

### 6. `/app/answer.json`
Write a JSON object with **at least** these keys (exact names matter):

- `"main_branch": "main"`
- `"recovered"`: list containing the restored path
  `"writing/sketches/story-notes.txt"`
- `"recovered_present"`: `true`
- `"bundle_branches"`: `["on-guide", "fieldnotes"]`
- `"site_pages"`: the full list of generated site pages you used above.
- `"deploy_executable"`: `true`
- `"listing_preserved"`: `true`
- `"bare_repo": "/srv/git/marlow.git"`
- `"ssh_user": "gitdev"` and `"password": "lantern-9"`

(The oracle also fills convenience keys; the verifier only checks the above.)

## The `repair` subcommand (hidden scenarios reuse the SAME script)

The verifier will run `python3 /app/solve.py repair --home DIR` on fresh,
self-contained git scenarios. Each `DIR` contains:

- `DIR/site` — a git repo (its default branch is unknown you; see
  `default_branch`),
- `DIR/bundles/` — zero or more bundle files,
- `DIR/plan.json`:

```json
{
  "scenario": "…",
  "default_branch": "…",
  "lost": {"path": "some/rel/path"} | null,
  "bundles": [{"filename": "x.bundle", "branch": "thebranch"}, ...]
}
```

`repair` must:

1. if `lost` is non-null and a branch named `default_branch` actually exists in
   the repo, restore that relative path onto `default_branch` with the exact
   bytes it has in history (it may live in a stash entry, or on another local
   branch) and commit it there.
2. for each `bundles` entry whose file exists, import that bundle and create a
   local branch named `branch` at the bundle's HEAD.
3. never crash. Print a single JSON object to stdout with at least:
   `"ok"` (`bool`), `"scenario"`, `"has_target"` (`bool`, is `default_branch`
   present), `"recovered"` (list of paths actually restored), and a map
   `"branches"` of branch->sha (missing bundles get a `null` value).

`ok` = (`has_target` AND lost-work satisfied AND every listed bundle branch
reachable). "bundle" a missing bundle input or bundle ref is a decline, not a
crash. No behavior other than what this section specifies.

## Constraints

- Work under `/app` only; do not read `/tests`. The image is minimal Ubuntu
  with `git`, `ssh`, `sshpass`, `sshd`, `python3`. No systemd: run sshd directly
  (prepare `/run/sshd`, then `/usr/sbin/sshd`).
- Running as root is fine.
- All state creation (site pages, branch recovery, user creation, sshd, bare
  repo) belongs inside `/app/solve.py`. A pristine image plus your two
  deliverable files must reproduce the whole stack from nothing but the seed
  fixtures.