# Serial console: a long-lived line-echo TCP service

You are implementing a small "serial console" style networking service using only the
Python standard library. The service is a long-lived TCP server that listens on
`127.0.0.1` port `2323` and echoes back the lines it receives (like a terminal attached
to a remote console).

## Protocol

- A client opens a TCP connection to `127.0.0.1:2323`.
- The client sends a single text line `PING\n` (the five characters `P I N G` followed by
  a newline).
- The server reads the line and sends back the **exact same text** (`PING\n`) as the
  reply.

## Deliverables

Write two files:

1. `/app/console_server.py` — the long-lived server process. It must bind `127.0.0.1`
   port `2323`, accept connections, and for each connection read lines and echo each
   line (the bytes received, including the trailing newline) back to the client. It runs
   indefinitely (never exits on its own). A clean implementation uses
   `socket.socket`, `bind`, `listen`, `accept`, and per-connection `recv`/`sendall`
   (a thread per connection is fine).

2. `/app/console_client.py` — a short client that connects to `127.0.0.1:2323`, sends
   `PING\n`, reads the echoed reply, and prints it to stdout (the printed text should be
   `PING`, optionally followed by a newline).

## Steps to finish

1. Write both files.
2. Start the server in the background (e.g. `python3 /app/console_server.py &`).
3. Run the client (`python3 /app/console_client.py`) and confirm it prints `PING`.
4. If it does, your solution is correct.

Leave `/app/console_server.py` and `/app/console_client.py` in place when you are done.