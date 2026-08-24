# Git-backed, branch-aware HTTPS deployment pipeline

You are standing up a self-hosted Git deployment pipeline for a small static website. The
goal is: pushing a branch to a bare Git repository over SSH must deploy that branch's
contents to its own web-visible directory, served over HTTPS by Nginx. You must build the
pipeline from scratch and **prove it works from the client side**.

## Pre-existing environment (do not modify)

- A system user `git` exists (home `/home/git`), along with an SSH keypair. The **private**
  key lives at `/app/deploy/keys/id_ed25519` and its matching public key is already installed
  in this host's SSH server as `/home/git/.ssh/authorized_keys`. You may use
  `/app/deploy/keys/id_ed25519` as the SSH identity for any Git client that connects to this
  host as user `git`.
- `/srv/git/` and `/srv/www/` exist and are owned by `git`.
- Nothing else has been configured: there is no bare repository, no hook, no Nginx config,
  no TLS certificate, and `sshd`/`nginx` are not yet running.

## What you must deliver (an end-to-end deployment path)

1. **Bare Git repository** at `/srv/git/site.git` (owned by `git`). It must be reachable via
   Git-over-SSH as `git@localhost:/srv/git/site.git` (transport: SSH, user `git`,
   host `localhost`).

2. **SSH server** (`sshd`) running so the remote Git transport above works. Make sure host
   keys exist (`ssh-keygen -A`) before starting. The only authentication needed is the
   supplied SSH key for user `git`.

3. **post-receive hook** at `/srv/git/site.git/hooks/post-receive`. For every pushed branch
   head, it must deploy that branch's exact tree into `/srv/www/<branch>/` (e.g. a push of
   branch `main` replaces the contents of `/srv/www/main/` with the pushed tree). Removing a
   remote branch must remove its deploy directory. (The hook runs under the `git` account
   that performed the push.)

   A robust way to export a tree without touching the bare repo's on-disk working state is
   `git --git-dir=/srv/git/site.git archive <commit> | tar -x -C <deploydir>`.

4. **Nginx** must serve the deployments over **HTTPS (TLS)**, one vhost per branch, with
   these two vhosts minimum:

   | URL                          | document root        |
   |------------------------------|----------------------|
   | `https://localhost:8443/`    | `/srv/www/main`      |
   | `https://localhost:8444/`    | `/srv/www/staging`   |

   Both listen on `ssl`; the certificates are self-signed for `localhost`. Store the TLS
   certificate and private key at `/etc/nginx/ssl/fullchain.pem` and
   `/etc/nginx/ssl/privkey.pem` (create them with `openssl`). Place your server blocks in
   `/etc/nginx/conf.d/deploy.conf`. Nginx must be **running**.

5. **Nginx must keep running** and `sshd` must keep running after you finish. Both consume
   one listening network port each.

## Test from the client side (do this before you finish)

Using `/app/deploy/keys/id_ed25519` as your SSH identity, clone `git@localhost:/srv/git/site.git`
into a scratch directory, and verify the whole round-trip:

1. In the clone, create `index.html` containing the marker string `CLIENTMAIN143`, commit to
   the `main` branch, and push. Then `curl -k https://localhost:8443/` must contain
   `CLIENTMAIN143`. `/srv/www/staging/` must NOT contain `CLIENTMAIN143`.
2. Create a `staging` branch from the clone, set `index.html` to contain `CLIENTSTAGING731`,
   commit, and push. Then `curl -k https://localhost:8444/` must contain `CLIENTSTAGING731`,
   and `/srv/www/main/` must NOT contain `CLIENTSTAGING731`.

Leave the pipeline running when you are done. The final state (bare repository + hook +
running Nginx+sshd on the listed ports) is what will be re-verified.