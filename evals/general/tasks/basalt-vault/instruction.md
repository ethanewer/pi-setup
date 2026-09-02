# Basalt Vault — maze exploration over HTTP

## Objective

A service called **Basalt Vault** hosts one or more maze instances over a local
HTTP/JSON API. Each maze is an identity-labelled grid whose layout is unknown to
you: you can only learn it by exploring, cell by cell. You must author
`/app/grid.py` — a self-contained Python 3 client (stdlib only; `urllib` is
enough) that, given a maze id, connects to the service, opens a session, fully
explores the unknown grid, collects the treasure, reaches the exit, registers
the session, and writes the fully explored map plus the winning move list to a
file.

Produce two deliverables:

1. `/app/grid.py` — the executable explorer described below.
2. `/app/map.txt` — the map for the sample maze, produced by actually running
   your explorer against the live service.

## The service

The service ships read-only at `/app/vault_server.py`. It is started like this:

```
python3 /app/vault_server.py --port <PORT> --fixture <FIXTURE_JSON>
```

All interaction is over HTTP at `http://127.0.0.1:<PORT>`. Every call is
`POST /<endpoint>` with a JSON body `{"id": "<maze_id>"}`; a `move` call adds
`"r"` and `"c"`:

| endpoint | payload | returns |
|----------|---------|---------|
| `start` | `{"id": m}` | `ok`, `pos` (start `[r,c]`), `rows`, `cols` |
| `examine`| `{"id": m}` | `ok`, `pos`, and `up`/`down`/`left`/`right` cell chars of the four neighbours |
| `move` | `{"id": m, "r": r, "c": c}` | `ok`, `pos`, `cell`; an error for a wall, out-of-range, or non-adjacent destination |
| `state` | `{"id": m}` | `ok`, `pos`, `collected`, `finished`, `alive`, `score`, `registered` |
| `finish` | `{"id": m}` | success only when called from the **exit** cell |
| `register` | `{"id": m}` | `ok`, `registered` |
| `status` | `{"id": m}` | full details: `exit`, `treasure`, `start`, `walls`, dims |
| `GET /ping` | — | `{"ok": true}` (liveness) |

Cell characters: `.` open passable, `#` wall, `T` treasure, `E` exit, `S`
start. `T`/`E`/`S` cells are passable. A `move` that lands on the treasure cell
automatically collects it. Calling `finish` anywhere other than the exit
permanently fails the game (`alive=false`). Registering finalizes the session.
The map must be written only after the session is finalized.

Scoring: `250` for collecting the treasure, `50` for finishing on the exit. The
maximum attainable score is **300**.

## `/app/grid.py`

Exact interface:

```
python3 /app/grid.py <maze-id> [--port PORT] [--out PATH]
```

- `<maze-id>` is required — the exact maze instance to solve.
- `--port` (default `8123`); base URL is `http://127.0.0.1:<PORT>`.
- `--out` (default `/app/map.txt`).

Your program must:

1. **Target the exact maze.** Only solve the maze whose id equals the command
   argument, even if the fixture contains more mazes.
2. **Explore the unknown grid.** From `start`, use `examine` + `move` to map
   the reachable area. Physically move onto every passable cell (only adjacent,
   in-range, non-wall steps), recording walls and the `S`/`T`/`E` markers you
   observe.
3. **Collect the treasure** by landing on `T`.
4. **Reach the exit** and call `finish` only once your player stands on the exit
   cell.
5. **Register** the session, then write the map.
6. **Write `--out`** in the exact format below and exit `0`.

### Map file format

```
BASALT-VAULT-MAP
maze=<id>
rows=<R>
cols=<C>
<grid row 0>
<grid row 1>
...   exactly R rows after the headers, each with C cells
MOVES
<sr>,<sc>-><dr>,<dc>
...
END
```

- Each grid row line holds the row's `C` cells separated by single spaces.
  Characters: `#` wall, `.` open, `S` start cell, `T` treasure cell, `E` exit
  cell. The map must be the **complete** grid — every wall and every passable
  cell present.
- The `MOVES` section lists every move you made, one line each, in
  `source->destination` notation. Each coordinate is a **zero-indexed
  `row,column` pair** (two comma-separated integers). The traversal must start
  at the first cell, make only single-step orthogonally-adjacent moves between
  passable (non-wall) cells, end at the exit cell, and together visit every
  passable cell in the maze (the whole grid is explored).

## Development run

The shipped fixture begins with the maze id `maze-0` (14 rows x 14 cols, start
at `[0,0]`). To build and produce the deliverable:

```
python3 /app/vault_server.py --port 8123 --fixture /app/vault_fixtures.json &
sleep 1
python3 /app/grid.py maze-0 --port 8123 --out /app/map.txt
```

This must leave `/app/map.txt` present. Do not delete or modify
`/app/vault_server.py` or `/app/vault_fixtures.json` — they are needed again
later.

## Verification

Your `/app/grid.py` is re-run against a fresh service instance for the sample
maze and for hidden mazes. Hidden mazes follow the same service and map contract
but use different ids and layouts, including edge cases: a narrow single-column
corridor, a single-row ribbon, sparse walls, and a fixture that also contains a
decoy maze (only the maze named on the command line may be solved; the decoy must
remain untouched). Every run is checked for:

- live game **score 300** with the treasure collected, finished on the exit,
  still alive, and the session registered;
- `/app/map.txt` grid line matching the exact maze geometry;
- every `MOVES` line being a legal zero-indexed adjacent move;
- the traversal starting at `start`, ending at `exit`, and visiting every
  passable cell.

Write the explorer generically so it solves any such maze from only the id and
the live service.