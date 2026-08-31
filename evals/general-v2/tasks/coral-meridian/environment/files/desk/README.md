# Coral Meridian tide desk — operator notes

The bureau runs one raw TCP "tide desk" on loopback. It is **not** started
automatically; operators bring it up with:

    python3 /app/desk/gauge.py &

It listens on `127.0.0.1` at the port in `/app/desk/desk.toml` ([desk] port,
default 47231) and serves the station files in `/app/desk/stations/*.json`
(each file: `{"station": "<name>", "samples": [[t, v], ...]}`).

## Wire protocol (STRICTLY one request per turn)

One TCP connection, newline-terminated text lines, one JSON reply line per
request, in this order. Never pipeline requests; the server answers exactly
one reply per request line.

1. `HELLO <name>` — opens the session (per-connection). Reply:
   `{"ok":true,"kind":"hello","session":"<16hex>","desks":["<station>",...]}`
   (`desks` is the sorted station list).
2. `READS <station>` — needs an open session, else `{"ok":false,"error":"no-session"}`.
   Reply for a known station:
   `{"ok":true,"kind":"reads","station":"..","samples":[[t,v],..],"count":N,"peak":[t,v]}`
   Unknown station: `{"ok":false,"error":"unknown-station","station":".."}`.
3. `EXTREME <station> <high|low>` — needs a session. Reply:
   `{"ok":true,"kind":"extreme","station":"..","which":"high|low","when":T,"value":V}`
4. `BYE` — reply `{"ok":true,"kind":"bye"}` and the server closes the connection.

Definitions used everywhere:
- **peak** sample of a station = max `v`; ties broken by the **smallest `t`**.
- **trough** = min `v`; ties broken by the smallest `t`.

Malformed/unknown/out-of-order requests get `{"ok":false,"error":...}` and
both the connection and the server stay alive. Never modify the fixtures
under `/app/desk/`.
