# willow-bridge

You work for the **Willow Bridge** field-support team. They are standing up an
on-premises analytics notebook that must (a) listen only on the loopback interface
so it is never reachable off the machine, and (b) filter a stream of IP records with
a strict dotted-quad matcher. Your job is to produce **two self-contained /app
artifacts**, each of which the grader will later run against inputs it has never shown
you.

## Deliverables

| Path | What it is |
|------|------------|
| `/app/jupyter_server_config.py` | A Jupyter **Server config file** that the `jupyter server` CLI will load (`jupyter server --config=/app/jupyter_server_config.py`) and that dictates binding, port, and authentication. |
| `/app/ipv4_octet.awk` | A **gawk** program that reads one IP token per line and emits an exact label per line, using one self-contained IPv4 regular-expression fragment. |

Build both so they satisfy the contracts below **exactly**. Do not modify anything
under `/app` that belongs to the image (e.g. keep `/app/sample_ips.txt` untouched).

---

## Part 1 — Jupyter Server configuration (`/app/jupyter_server_config.py`)

The file is a normal Python config module executed by the Jupyter config loader; it
must define a module-level `c = get_config()` and set:
- `c.ServerApp.ip = "127.0.0.1"`  (and the legacy alias `c.NotebookApp.ip = "127.0.0.1"`).
- The listen **port**, taken from the environment variable **`WILLOW_NOTE_PORT`**:
  - if `WILLOW_NOTE_PORT` is an integer between 1 and 65535, the port equals it.
  - if it is unset, empty, or **not an integer**, the port is the default **`8666`**.
  - Set both `c.ServerApp.port` and `c.NotebookApp.port`.
- `open_browser` is `False` for both `ServerApp` and `NotebookApp`.
- Authentication is **disabled** for loopback use: `token == ""` and `password == ""`
  on **both** `ServerApp` and `NotebookApp`.

When the verifier runs

```bash
WILLOW_NOTE_PORT=8791 jupyter server --config=/app/jupyter_server_config.py \
    --no-browser --allow-root --ServerApp.root_dir=/tmp/wb
```

the server must end up listening on `tcp://127.0.0.1:8791` and answer
`GET /api/status` with HTTP `200` (a token-protected Jupyter Server answers `403`,
so your config must actually switch that off).

Hidden runs will exercise several cases:
1. `WILLOW_NOTE_PORT=8791` → must listen on `127.0.0.1:8791`, `/api/status` = `200`.
2. `WILLOW_NOTE_PORT=8442` → must listen on `127.0.0.1:8442`, `/api/status` = `200`.
3. `WILLOW_NOTE_PORT` unset → must fall back to the documented default port **`8666`**.
4. `WILLOW_NOTE_PORT=midnight-13` (non-integer) → must fall back to **`8666`**.

Notes:
- The verifier launches the server itself in a background process; you do not need to
  start it. Your file must load without a Python trace-back and let the server bind.
- If the wrong thing binds (e.g. it ignores `WILLOW_NOTE_PORT`), the check for the given
  case fails.
- Keep the file dependency-free (standard library only) and robust to a bad
  `WILLOW_NOTE_PORT` value.

---

## 2 — IPv4 classifier (`/app/ipv4_octet.awk`)

Write a gawk program such that, for **every line** of an input file (or stdin), it
**trims** leading/trailing ASCII whitespace (spaces and tabs) from the line and emits
exactly one output line:

```
VALID\t<trimmed>        (if the trimmed line is a well-formed IPv4 address)
INVALID\t<trimmed>      (otherwise)
```

Note: the label and the trimmed text are separated by a single TAB. There is one
output line per input line — even for empty/blank lines (those are `INVALID\t`). Emit
nothing else to stdout.

The program must decide `VALID` strictly as follows. The trimmed line is a valid IPv4
dotted-quad **iff** it is exactly four octets separated by single dots, where every
octet is a decimal number in `0..255`, written **without any leading zero** (a single
`0` as the zero octet is allowed), and the whole string is self-contained (not
embedded in a longer alphanumeric token, no extra dots, no signs, no decimals or
exponent forms, no whitespace inside).

Examples of trimmed lines:

| input (trimmed)        | label    |
|------------------------|----------|
| `192.168.1.77`         | VALID    |
| `0.0.0.0`              | VALID    |
| `255.255.255.255`      | VALID    |
| `10.203.14.7`          | VALID    |
| `256.1.2.3`            | INVALID  (octet over 255) |
| `301.0.0.0`            | INVALID  |
| `192.168.01.4`         | INVALID  (leading zero) |
| `09.10.11.12`          | INVALID  |
| `1.2.3`                | INVALID  (not 4 octets) |
| `1.2.3.4.5`            | INVALID  (5 octets) |
| `192.168.1.1.`         | INVALID  (trailing dot) |
| `.192.168.1.1`         | INVALID  (leading dot) |
| `a1.2.3.4`             | INVALID  (embedded in longer token) |
| `1.2.3.4x`             | INVALID  |
| `-1.2.3.4`             | INVALID  |
| `1e2.3.4.5`            | INVALID  |
| `1.2.3..5`             | INVALID  |
| `1.2.3.4 `             | VALID    (trailing space trimmed; a hard trim) |

Build it so the matcher rests on a **single self-contained IPv4 regular expression**
(octet components with `0..255`, no leading zeros, four groups, full-string anchors).
The hidden corpora (a handful of genuinely different files — a mixed legal/illegal
corpus, a leading-zero/out-of-range stress corpus, and a surrounding-token / whitespace
corpus, including empty lines) are checked for a **per-line** `VALID`/`INVALID` label
matching the table above on the trimmed text.

Contract reminders:
- Run form that must work: `gawk -f /app/ipv4_octet.awk <file>` and with stdin when
  no file argument is given.
- Only gawk built-in features; no external subprocesses.
- `<trimmed>` is the trimmed text exactly as it appeared after trimming
  (the leading/trailing whitespace is gone, everything else is preserved byte-for-byte).

## What the verifier rewards

The verifier runs your exact two deliverables on unseen inputs:
1. launches Jupyter Server using your config in the four port scenarios above and
   requires the correct loopback bind + tokenless `200`;
2. runs `gawk -f /app/ipv4_octet.awk` over several hidden corpora and requires
   every emitted label to equal the independent ground truth.

Both parts must pass for the task to succeed. Do not try to read `/tests` (it is
unavailable to you), and solve it purely from this contract.