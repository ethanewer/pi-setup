# Coral Meridian tide desk — capture the peak report

You are the duty analyst at the **Coral Meridian** tide-gauge bureau. The
bureau's raw TCP **tide desk** sits on loopback (fixtures in `/app/desk/`;
see `/app/desk/README.md` for the operator notes and the full wire protocol).
The desk is **not** running — bring it up yourself with
`python3 /app/desk/gauge.py &` (port comes from `/app/desk/desk.toml`).

The desk speaks a **strictly turn-based** text protocol: you send ONE request
line, you read ONE JSON reply line, then (and only then) you may send the next
request. A `READS`/`EXTREME` is only answered after a `HELLO` on the same
connection. Requesting before handshaking, pipelining, or blocking forever on
a reply will hang or fail your tool — respect the turn discipline.

## Deliverables (both required)

1. `/app/tide.py` — a runnable Python program (stdlib only, **no third-party
   packages**) with this interface:
   - `python3 /app/tide.py` (no args) — the full run:
     1. Connect to `127.0.0.1:<port from /app/desk/desk.toml>`.
     2. Send `HELLO analyst` and read the reply (note the `desks` list).
     3. For **every** station in that list, send `READS <station>` and read
        the reply.
     4. Pick the station whose `peak` value is the **highest across all
        stations**. If two or more stations tie on that value, pick the
        **lexicographically smallest station name**.
     5. Send `EXTREME <chosenStation> high` and read the reply.
     6. Overwrite `/app/peak.json` with that EXTREME reply as a **single JSON
        line** (the exact `{"ok":true,"kind":"extreme",...}` object).
   - `python3 /app/tide.py fetch <station>` — connect, `HELLO analyst`, then
     a single `READS <station>`, and **print the raw reply JSON line to
     stdout** (nothing else). For an unknown station the desk returns
     `{"ok":false,...}`: your tool must print that reply and exit with
     status 0 — it must never hang or crash.
   Your program must compute everything **live from the protocol** — never
   hard-code station names, sample values, or the port.

2. `/app/peak.json` — the EXTREME reply your program produces for the
   **provided** station data (run `python3 /app/tide.py` with the provided
   fixtures in place).

## What the grader does

It boots **fresh desk servers on station data you have never seen** (different
station names, different samples, at least one case where two stations **tie**
on the peak value — your tie-break must pick the lexicographically smallest
name), then:

1. runs `python3 /app/tide.py` and checks `/app/peak.json` matches the
   correct EXTREME reply for that hidden data;
2. runs `python3 /app/tide.py fetch <hidden-station>` and compares stdout to
   the desk's READS reply;
3. runs `python3 /app/tide.py fetch definitely-not-a-station` and requires the
   `{"ok":false,...}` reply on stdout with exit status 0, within a timeout;
4. re-checks `/app/peak.json` and `/app/tide.py` against the **provided**
   fixtures, and confirms the desk server is still alive after all of the
   above.

A tool that hard-codes the provided station names/values, the port, or that
breaks the one-request-per-turn discipline fails on the hidden cases.

## Constraints

- Work only inside the container. Do **not** modify anything under `/app/desk/`
  or `/app/desk.toml`-adjacent fixtures. Your changes are confined to
  `/app/tide.py` and `/app/peak.json`.
- No network beyond loopback; standard library only.
- `/tests` and `/solution` are not available to you.
