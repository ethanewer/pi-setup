# Drive a line-oriented interactive session tool

Build a small line-oriented tool at **`/app/session.py`**. It must read commands
from standard input (one per line) and write exactly one response line per
command to standard output, until end-of-input (EOF). It implements a stateful
session so it can be driven by an arbitrary command stream — not just the sample
below.

## Command protocol

Read the file `/app/session_contract.txt` for the authoritative spec. A session
advances through three states: **EMPTY** (nothing opened yet), **OPEN** (a
session is live), and **CLOSED** (after a `CLOSE`).

| Command | Valid in | Response |
|---|---|---|
| `OPEN <name>` | EMPTY | `OK` |
| `PUT <key> <value>` | OPEN | `OK` |
| `GET <key>` | OPEN | `VALUE <value>` or `ERROR missing` |
| `LIST` | OPEN | `KEYS k1,k2,...` |
| `CLOSE` | OPEN | `CLOSED` |

A `PUT` stores or overwrites its key. `LIST` reports the stored keys separated
by commas in **lexicographic order**; when no keys are stored it prints exactly
`KEYS` (no trailing comma or space). Each token (`name`, `key`, `value`) is a
single whitespace-delimited word; values have no spaces.

## Edge cases your tool MUST handle (these are verified)

- **Precedence — the command name is checked before the state.** If the first
  token is not one of the five command names (`OPEN`, `PUT`, `GET`, `LIST`,
  `CLOSE`), the response is `ERROR unknown`, in **any** state (EMPTY, OPEN, or
  CLOSED), and the state does not change.
- A **recognised** command received while in state EMPTY or CLOSED (i.e. not
  currently open) responds `ERROR not open` and does **not** change state. In
  particular, a `CLOSE` attempted while EMPTY responds `ERROR not open` and
  does **not** close the session: it stays EMPTY and a later `OPEN <name>`
  still succeeds.
- `OPEN` given while already open responds `ERROR open` (no state change).
- State checks come before argument checks: e.g. `GET` with no key while EMPTY
  is `ERROR not open`, not `ERROR bad`; `PUT k` while EMPTY is `ERROR not
  open`, not `ERROR bad`.
- While OPEN, a known command whose required arguments are missing (e.g. `PUT
  k` or `GET` alone; `OPEN` with no name) responds `ERROR bad`.
- `GET` for a key that has never been stored (or was overwritten) responds
  `ERROR missing`.
- After a successful `CLOSE`, every further **recognised** command (including
  `OPEN`, `PUT`, `GET`, `LIST`, `CLOSE`) responds `ERROR not open`; an
  unrecognised name still responds `ERROR unknown` (the name check comes
  first). Re-opening after a `CLOSE` is not allowed.
- Blank lines produce **no** output and are skipped.
- Commands are case-sensitive. The program must not hang; it must read to EOF
  and terminate cleanly, producing exactly one output line per command (blank
  lines excluded).

## Requirements

- Write the program to `/app/session.py`. Do **not** modify anything else under
  `/app`, including `/app/session_contract.txt`. `/app/session_contract.txt` is
  input and must be left untouched.
- The tool must work on **any** valid command stream, not just the examples, so
  write it as a general state machine. The verifier runs it on fresh command
  streams that probe every edge case listed above.

## Sample

Input:
```
OPEN balance
PUT color blue
LIST
GET color
CLOSE
GET color
```
Output:
```
OK
OK
KEYS color
VALUE blue
CLOSED
ERROR not open
```
