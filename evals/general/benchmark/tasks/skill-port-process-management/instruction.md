# Port / process management

Write two shell scripts for **port and process management** on this machine.

**`/app/findport.sh`** — Prints the PID(s) of whatever process(es) are currently listening on a TCP port. It takes the port number as its first argument (`$1`, an integer). It should print one PID per line (numeric only, nothing else), e.g.:

```
12345
```

Return exit code 0 if at least one listener was found and printed, non-zero otherwise.

**`/app/killport.sh`** — Kills every process listening on a given TCP port. It takes the port number as its first argument (`$1`). It should terminate those processes and return 0 once all listeners on that port are gone, or non-zero on failure.

You may use `ss`, `lsof`, and/or `fuser` (with any appropriate flags) to find listeners, and the OS kill primitive to stop them. These tools are available in the environment.

The verifier will: start a server listening on `127.0.0.1:8792`, run your `findport.sh` against port 8792 (expecting a bare numeric PID back), then run your `killport.sh` against 8792, then confirm no process is still listening on that port.