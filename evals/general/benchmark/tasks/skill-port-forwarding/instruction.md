# TCP port forwarding

Set up a **TCP port-forwarding tunnel** on this machine.

Write a Bash script at `/app/forward.sh` with this contract:

- When run (as root), it must establish a TCP port-forwarding tunnel: every inbound TCP connection to **127.0.0.1:8090** is forwarded to **127.0.0.1:9097**.
- It must start the tunnel **in the background** and return to the caller immediately (i.e., `bash /app/forward.sh` should complete within a moment, not hang).
- Before creating the (new) tunnel it should clear any leftover listener already bound to port 8090 so a stale tunnel does not mask a fresh one (for example release/kill any prior process on that port).
- The script itself should return exit code 0 on success and non-zero on failure.

`socat` is available (its universe distribution is already installed). A straightforward implementation uses
`nohup socat TCP-LISTEN:8090,fork,reuseaddr TCP:127.0.0.1:9097 &`
(possibly with a preceding `fuser -k` style cleanup).

The verifier will: start a small HTTP server on `127.0.0.1:9097`, run your `/app/forward.sh`, then issue an HTTP request to `http://127.0.0.1:8090/...` and confirm the response matches what the 9097 server served. That proves the forward tunnel works end to end.