# Git-backed multi-branch HTTPS deployment (hard)

You are standing up a three-branch, HTTPS-served deployment pipeline backed by a bare Git
repository reached over SSH. It must be fully working from the client side: pushing a branch
must (re)deploy only that branch's tree to its own web root; deleting a branch must remove
that branch's deployment. Nginx serves each branch over TLS on its own port. Both `sshd` and
`nginx` must be left **running**, and the hook must run with correct permissions even though
the deploy directories were pre-created with restrictive, root-owned, stale contents.

## Pre-existing environment

- System user `git` (home `/home/git`). Its SSH keypair: private key at
  `/app/deploy/keys/id_ed25519`, public key already installed at `/home/git/.ssh/authorized_keys`.
  Use this key as the client identity for any Git-over-SSH connection to host `localhost`,
  user `git`.
- Three deploy directories already exist but are **owned by root** and contain stale marker
  pages: `/srv/www/main/index.html`, `/srv/www/staging/index.html`, `/srv/www/dev/index.html`.
  Your post-receive hook will run as the `git` account; it will NOT be able to overwrite these
  unless you fix ownership/permissions. First diagnose and fix this — a deployment that cannot
  overwrite stale content is broken.

## Build the pipeline

1. **Bare repository** at `/srv/git/site.git` (owned by `git`), reachable over SSH as
   `git@localhost:/srv/git/site.git`.
2. **SSH server running** (`ssh-keygen -A` then start `sshd`). Git-over-SSH must work with
   the provided key.
3. **post-receive hook** at `/srv/git/site.git/hooks/post-receive` with these behaviors:
   - For each pushed branch head, replace the contents of `/srv/www/<branch>/` with that
     branch's exact pushed tree. Multi-branch pushes (multiple ref updates in one push
     command) must deploy **each** branch independently.
   - When a branch is deleted (`git push origin :<branch>`), remove `/srv/www/<branch>/`
     entirely.
   - It must be able to overwrite the pre-existing root-owned stale files in the deploy
     directories (fix permissions so the git-run hook can write).
   - Recommended: `git --git-dir=/srv/git/site.git archive "<commit>" | tar -x -C /srv/www/<branch>`.
4. **Nginx** serving HTTPS (self-signed, `CN=localhost`, cert/key at
   `/etc/nginx/ssl/fullchain.pem` + `/etc/nginx/ssl/privkey.pem`). Three vhost server
   blocks under `/etc/nginx/conf.d/`:

   | port | document root |
   |------|---------------|
   | `8443` | `/srv/www/main` |
   | `8444` | `/srv/www/staging` |
   | `8445` | `/srv/www/dev`   |

   Nginx must be **running**.

5. **Coordinating services**: make sure Nginx and sshd share the host without port clashes
   and stay up after you finish. Debug any service that fails to stay up, and fix port or
   permission issues rather than restarting per-second.

## Prove it from the client side (before finishing)

1. Clone `git@localhost:/srv/git/site.git`.
2. Commit `index.html` with `DEVROOT_a1f2` on the `main` branch; create a `dev` branch and
   commit `DEVBRANCH_eek3` in it. **Push both refs in a single `git push` command**.
   - `curl -k https://localhost:8443/` must contain `DEVROOT_a1f2` and NOT `DEVBRANCH_eek3`.
   - `curl -k https://localhost:8445/` must contain `DEVBRANCH_eek3` and NOT `DEVROOT_a1f2`.
3. Push a throwaway branch with a marker page, confirm its `/srv/www/<branch>` appears, then
   `git push origin :<branch>` (delete) and confirm `/srv/www/<branch>` is removed / its URL
   stops serving.

Leave everything running. That final state (repo + hook + running sshd & nginx on those three
ports, writable deploy dirs) is what will be re-tested.