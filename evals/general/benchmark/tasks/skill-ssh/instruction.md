# SSH

An **OpenSSH server** is running on this machine (started at container boot on `127.0.0.1:22`).

- The user `alice` exists, with a home directory `/home/alice`.
- `/home/alice/secret.txt` contains a single line of text.
- Your SSH **private key** is at `/keys/agent_key` (ed25519; you are its owner). The matching public key is already installed in `alice`'s `authorized_keys`.

Your task is to use the **SSH client** to connect to `alice@127.0.0.1`, remotely execute the command `cat /home/alice/secret.txt`, and save its output to `/app/ssh.txt`.

Run something like:

```bash
mkdir -p /app
ssh -i /keys/agent_key -o StrictHostKeyChecking=no alice@127.0.0.1 \
    'cat /home/alice/secret.txt' > /app/ssh.txt
```

Notes:
- This must go over the **SSH protocol** (connect to the running server), not read the file directly from the local filesystem.
- The server's host key is self-signed; the `-o StrictHostKeyChecking=no` option is provided so you do not need an interactive host-key prompt.
- The verifier checks that `/app/ssh.txt` contains exactly the single line read from the remote file (`ssh-secret-hello-world`).