# Kestrel Vault — seal the vault and exit cleanly

You are the night warden of Kestrel Vault. The vault's console runs a small
interactive game, `/app/vault.py`, that records the sealing ceremony. Your job
is to **play the game to its ending and exit it via its normal `quit` command**
so the in-memory session state is flushed to the SQLite database — then hand
over a reusable driver program that can do the same on fresh vault scenarios.

Work entirely in `/app`. Do not modify `/app/vault.py` or `/app/scenario.json`
— they are fixtures (the verifier hashes them). You may add helper scripts, but
the deliverables below must exist at exactly the listed paths.

## Environment

- Working directory `/app`; Python 3.12 (`python3`) available.
- The game: `python3 /app/vault.py <scenario.json> [--db <db_path>]

  It reads one command per line from stdin and answers with a single response
  line per command (flushed). On startup it prints a banner:
  `VAULT-READY keeper=<name> containers=<n>`.
  State is written to the SQLite database **only** on the clean `quit` path;
  killing, aborting, or letting stdin hit EOF writes nothing.

### Game protocol (names and gems are single words)

| command          | response |
|------------------|----------|
| `look`           | `CONTAINERS <name1, name2, ...>` (comma+space separated) |
| `search <name>`  | `FOUND <gem>` the first time, `EMPTY` afterwards, or `NO-SUCH-CONTAINER` |
| `take <gem>`     | `TAKEN <gem>`, or `ALREADY-HELD`, or `NOT-FOUND` |
| `place <gem>`    | `PLACED <gem>`, or `NOT-HELD` |
| `seal`           | `SEALED <ending message>` when every container's gem is placed, else `REJECTED missing=<k>` |
| `status`         | `HELD <csv> PLACED <csv>` |
| `quit`           | `BYE` — persists state, then the process exits 0 |
| anything else    | `UNKNOWN` |

To reach the ending: `look` to learn the container names, `search` every
container, `take` and `place` every gem found, then `seal`. The ending message
is the text after `SEALED ` on that response line — it is scenario-specific and
**not** given in this prompt; you must actually play to capture it.

### Database (written only by the clean `quit` path)

On `quit` the game creates/updates the SQLite file with tables:
- `sessions(id, keeper, gems_found, gems_placed, moves, completed)` — one row
  per session; `completed` is 1 only if the seal succeeded.
- `events(id, session_id, kind, detail)` — one row per `place` and per `seal`
  attempt (`kind` = `place` / `seal`).

## Deliverables (all must exist)

1. **`/app/solve.py`** — a general driver program that plays the game via its
   stdin/stdout protocol and exits it cleanly. CLI:
   ```
   python3 /app/solve.py <game_py> <scenario_json> <ending_out> <db_path>
   ```
   - Spawn `python3 <game_py> <scenario_json> --db <db_path>` (e.g. with
     `subprocess`) and drive it over pipes using **only** the documented
     protocol — do not read the scenario's `ending` field directly and do not
     fabricate the database; play the game.
   - It must be general: parse the `CONTAINERS` list from the game's own
     responses, search every container, take and place every gem found, seal,
     and quit. It must work on hidden scenarios with different keepers,
     container counts, names, gems, and endings.
   - Write the captured ending message to `<ending_out>` (the line alone, no
     leading/trailing whitespace or `\r`).
   - Exit 0 only after the game process has exited cleanly (exit code 0) with
     the database flushed.
2. **`/app/ending.txt`** — the ending message captured from the shipped vault
   (`/app/scenario.json`), produced by running
   ```
   python3 /app/solve.py /app/vault.py /app/scenario.json /app/ending.txt /app/state/vault.db
   ```
3. **`/app/state/vault.db`** — the flushed database from that same clean run
   (it must contain the session row with `completed=1` and the gameplay
   `events` rows — proof the game was exited via `quit`, not killed).

## What the verifier checks

- `/app/solve.py`, `/app/ending.txt` and `/app/state/vault.db` exist;
  `/app/ending.txt` equals the shipped scenario's true ending message;
  `/app/state/vault.db` has a `sessions` row with `completed=1`,
  `gems_placed=<number of containers>` and `moves > 0`, plus `events` rows
  (at least one `place` per gem and a successful `seal`).
- It **re-runs your driver** (`python3 /app/solve.py /app/vault.py
  <scenario> <out> <db>`) on hidden vault scenarios — 4 and 6 containers,
  different keepers/names/gems/endings — and applies the same ending and
  database checks to each run's fresh output paths.
- `/app/vault.py` and `/app/scenario.json` are byte-identical to their shipped
  contents.

No network access; standard library only.
