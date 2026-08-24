# SSH with DropBear

A **DropBear** SSH server (the lightweight SSH server/implementation often used in embedded/router environments) is running on this machine at **`127.0.0.1:2222`** (started at container boot).

- The user `bob` exists, with home directory `/home/bob`.
- `/home/bob/secret.txt` contains a single line of text.
- Your SSH **private key** is at `/keys/agent_key` (ed25519, OpenSSH format). The matching public key is already installed in `bob`'s `authorized_keys`.

Your task is to use an SSH client to connect **over SSH** to the DropBear server on port `2222`, remotely execute `cat /home/bob/secret.txt`, and save its output to `/app/drop.txt`.

Run something like:

```bash
mkdir -p /app
ssh -i /keys/agent_key -o StrictHostKeyChecking=no -p 2222 bob@127.0.0.1 \
    'cat /home/bob/secret.txt' > /app/drop.txt
```

Notes:
- This must go over the **SSH protocol** to the running DropBear server (`127.0.0.1:2222`) — do not read the local file directly.
- The server's host key is self-signed; `-o StrictHostKeyChecking=no` avoids an interactive host-key prompt.
- The verifier checks that `/app/drop.txt` contains exactly the single line read from the remote file (`dropbear-secret-here`).