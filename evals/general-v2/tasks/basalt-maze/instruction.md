# Dispatch the warehouse crawler through the navd maze

You are the shift engineer for the **basalt-maze** fulfilment depot. The
depot's crawler navigation daemon, `navd`, is a raw TCP text service on
loopback that tracks a single warehouse crawler on a walled grid. Your job is
to write a client that drives the `navd` protocol — plan a route, then step
the crawler to its goal one request at a time — and to use it to dispatch the
depot's crawler.

Everything about the service is discoverable inside the container:

- `/app/navd/navd.py` — the daemon itself (the wire format is documented in
  its docstring and implemented in `handle()`; read it).
- `/app/navd/README.md` — quick-start.
- `/app/navd/grid.json` — the depot's default grid.

Do **not** modify anything under `/app/navd/` — the daemon is the service your
client must interoperate with.

## Starting the service

    python3 /app/navd/navd.py /app/navd/grid.json 43770

It listens on **127.0.0.1** on the port you pass (the default depot port is
`43770`) and prints `LISTENING <port>` when ready. The grader runs its own
`navd` instances (same program, different grid files) on fresh ports.

## The navd wire protocol (summary — full detail in navd.py)

- **One request per connection.** The client opens a TCP connection to
  `127.0.0.1:<port>`, sends exactly **one text command line** terminated by
  `\n`, reads exactly **one JSON response line**, and the server closes the
  connection. Requests must not be pipelined; a second request on the same
  connection is ignored.
- `PLAN` — resets the crawler to the grid's start cell and replies
  `{"ok":true,"grid":{"rows":R,"cols":C},"start":{"row":r,"col":c},
  "goal":{"row":r,"col":c},"walls":[[r,c],...]}`. If `start == goal` the
  reply additionally carries `"status":"arrived"`, `"moves":0` and the
  arrival `"token"`.
- `STEP <dir>` with `dir` one of `N`, `S`, `E`, `W` — advances the crawler one
  cell (rows grow southward, cols eastward; 0-indexed). Replies:
  `{"ok":true,"status":"moving"|"arrived"|"blocked","pos":{"row":r,"col":c},
  "moves":n}`. `"blocked"` means the crawler stayed in place (wall or grid
  edge) — the move still counts. The reply with `"status":"arrived"` also
  carries the arrival `"token"` (a 40-hex string). Stepping after arrival
  yields `{"ok":false,"error":"already-arrived"}`.
- Unknown/garbage commands yield `{"ok":false,"error":"..."}` — your client
  must tolerate these replies without crashing.
- **Arrival token formula** (deterministic; the grader recomputes it):
  `sha256("navd-v1|<rows>x<cols>|<row>,<col>|<moves>").hexdigest()[:40]`
  where `<row>,<col>` is the crawler's final position and `<moves>` is the
  number of STEP commands issued to get there.

## Deliverables (both required)

1. `/app/dispatch.py` — a runnable Python client:
   ```
   python3 /app/dispatch.py <port> <output_json>
   ```
   It connects to `navd` on `127.0.0.1:<port>`, sends `PLAN`, computes a
   route from start to goal that never enters a wall or leaves the grid,
   then issues `STEP` commands (one request per connection, in order) until
   the crawler arrives. It must write a JSON result to `<output_json>` with
   exactly these keys:
   ```json
   {
     "grid":  {"rows": R, "cols": C},
     "start": {"row": r, "col": c},
     "goal":  {"row": r, "col": c},
     "steps": ["E", "N", ...],
     "final": {"row": r, "col": c},
     "moves": <number of steps issued>,
     "token": "<40-hex arrival token>"
   }
   ```
   - If the goal is **unreachable**, the program must detect this (it may use
     the returned `walls` list), print a diagnostic to stderr, exit with a
     **non-zero status**, and **not** create the output file. It must never
     hang.
   - `steps` must be a legal walk: applying them from `start` (skipping
     nothing, no off-grid or into-wall moves that end the walk short) ends at
     `goal`, and `final` is the crawler's actual final `pos` as reported by
     the daemon. `token` is the arrival token reported by the daemon.
2. `/app/route.json` — the result your program writes when run against the
   depot's default service:
   ```
   python3 /app/navd/navd.py /app/navd/grid.json 43770 &
   python3 /app/dispatch.py 43770 /app/route.json
   ```

## Edge cases the grader exercises (your client must handle all of them)

1. **Unseen grids** — the grader restarts `navd` with different grid files
   (different sizes, walls, starts, goals) on fresh ports and runs
   `python3 /app/dispatch.py <port> <out>`; your route, final position and
   token must be correct each time.
2. **`start == goal`** — the crawler is already at the goal; the correct
   result has `"steps": []`, `"moves": 0`, `final == start`, and the token
   the `PLAN` reply carries.
3. **Unreachable goal** — a grid where walls seal the goal off; your program
   must exit non-zero within a reasonable time and leave no output file.
4. Your client must not hang if the daemon closes a connection early or
   returns an error reply — fail fast with a non-zero status instead.

## Constraints

- Work only inside the container; do not modify `/app/navd/*`.
- Python 3.12 standard library only; **no network access** beyond the
  loopback `navd` service.
- The grader runs your program unchanged on unseen inputs — do not hard-code
  routes or tokens.
