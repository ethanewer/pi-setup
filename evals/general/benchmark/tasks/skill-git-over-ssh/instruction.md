A git repository is served over **SSH** on this machine. An OpenSSH server is already running (started at container boot) on the loopback address. A user `sshgit` exists, and its SSH private key is installed at `/keys/agent_key` (you are its owner). The repository is a bare repo at:

```
/home/sshgit/repos/team.git
```

Clone it over SSH into the new directory `/app/pulled`:

```
export GIT_SSH_COMMAND="ssh -i /keys/agent_key -o HostKeyAlgorithms=+ssh-ed25519 -o StrictHostKeyChecking=no"

mkdir -p /app
git clone sshgit@127.0.0.1:/home/sshgit/repos/team.git /app/pulled
```

This uses the SSH transport (not the file path or http) to fetch from `sshgit@127.0.0.1`.

After cloning, confirm `/app/pulled` is a git repository whose remote `origin` uses an SSH-style URL, and that its working copy contains `README.txt` with the exact single line:

```
ssh-hello
```

The verifier checks that `/app/pulled` is a cloned repository, that its origin remote URL is an SSH transport URL, and that `README.txt` has the exact content above.