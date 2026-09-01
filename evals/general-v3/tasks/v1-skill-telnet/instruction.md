# Telnet text-protocol server

There is a telnet-style text server running on **127.0.0.1 port 2323** on this machine. A script that implements the server is at `/app/server.py` and it is **not currently running** — you must start it first.

The server follows a simple line-based (telnet) protocol:

1. On connect, it sends one banner line: `BANNER-ELHO-7`.
2. After you send a single line ending with a carriage-return/newline (`\r\n`), it replies.
3. If the line you send is exactly `GIVE-KEY`, it replies with `KEY=<secret>`; otherwise it replies `ERR`.

The server records every line it receives (one per line) in `/app/server.log`.

## Your Task

1. Start the server by running the Python script at `/app/server.py` in the background.
2. Use the **telnet** client to connect to `127.0.0.1` on port `2323` (the telnet client program is already installed).
3. Once connected, send the command `GIVE-KEY`.
4. The server will reply with a `KEY=...` value. Write that exact key value (just `open-sesame-42`, no `KEY=` prefix, no trailing whitespace) to the file `/app/secret.txt`.

## Verification

- `/app/server.log` must contain a line equal to `GIVE-KEY` (proving the telnet-style command reached the server).
- `/app/secret.txt` must contain exactly the secret value the server returned.

Make sure you connect successfully and both artifacts end up on disk.