# Juniper Notch relay-station — operator manual

Juniper Notch relay-station **juniper-notch-77** sits on a mountain notch and
fans telemetry in all directions. It is reachable only over **loopback**
(`127.0.0.1`) inside this container. The relay is deliberately kept
unauthenticated so cluster peers can join without keys.

Everything the relay needs to know about its own endpoints lives in
`/app/relay/station.toml`. Read it to learn the bus and gate addresses.

## 1. The job bus (MQ over TCP)

The bus speaks **MQTT v3.1.1** on `127.0.0.1:31883` (see `station.toml`,
`[bus]`). No username/password is configured — a peer connects anonymously.
The inbox topic the worker views is `juniper/jobs`.

The relay worker (`/app/relay/worker.py`) subscribes to `juniper/jobs` and
applies **task directives**. A directive is a JSON message published to that
topic with **retain=true** so a worker that subscribes later still receives it.
It validates against this exact schema:

```json
{
  "job_id": "some-token",
  "kind":   "rebalance",
  "sector": "north",
  "payload": [3, 1, 4, 1, 5]
}
```

Rules (read them carefully — the worker enforces every one):

- `job_id` — non-empty `[A-Za-z0-9_-]` string, at most 64 chars.
- `kind` — must be exactly the string `"rebalance"`.
- `sector` — one of `"north"`, `"south"`, `"east"`, `"west"`.
- `payload` — a JSON array of 1 to 12 integers, each `0..100000`, no booleans,
  no floats.

A valid directive is applied and a receipt written to
`/app/relay/applied/<job_id>.result.json`. A directive that breaks any rule is
ignored (no receipt) and does **not** disturb the worker. To inject a task,
publish a valid directive JSON with retain=true to `juniper/jobs`. Use
`paho-mqtt` (already installed) — e.g.

```python
from paho.mqtt import client as mqtt
c = mqtt.Client()
c.connect("127.0.0.1", 31883)
c.loop_start()
c.publish("juniper/jobs", json.dumps(directive), qos=1, retain=True)
import time; time.sleep(1); c.loop_stop()
```

## 2. The survey gate (raw TCP text protocol)

`/app/relay/gate.py` is a raw TCP text server on `127.0.0.1:43979` (see
`[gate]` in `station.toml`), one logical request per connection turn. The
client connects with a plain `socket`, writes one line, and reads one JSON
response line.

- `MAP` — returns the active site map and a `target` coordinate:
  `{"ok":true,"kind":"map","target":{"row":R,"col":C},"sites":[{"name":...,"row":R,"col":C},...]}`.
- `SURVE <siteName>` — surveys a site named in the map and returns
  `{"ok":true,"kind":"site","site":...,"row":R,"col":C,"token":"<40hex>"}`.
  Unknown names return `{"ok":false,...}`.

To drive a survey: connect, send `MAP`, read the map, compute the site whose
(row,col) is nearest to `target` by **Manhattan distance** `|dr|+|dc|` (ties:
lexicographically smallest name), send `SURVE <thatSite>`, and record the
`site` reply. Example client outline:

```python
import socket, json
s = socket.create_connection(("127.0.0.1", 43979), timeout=5)
s.sendall(b"MAP\n")
map_resp = json.loads(_read_line(s))
# ... pick nearest site ...
s.sendall(("SURVE %s\n" % name).encode())
site_resp = json.loads(_read_line(s))
s.close()
```

(`_read_line` reads one newline-terminated line from the socket.)

## 3. When you are done

Leave behind, as directed by your job ticket:

- `/app/q.py` — your relay tool. Running `python3 /app/q.py` (no args) must (a)
  read the directive from `/app/job.json`, publish it retain=true to
  `juniper/jobs` on the bus, and (b) survey the gate and write the chosen
  site's JSON line to `/app/roundtrip.out`. It must also support two modes it
  could be asked to run by the grader:
  - `python3 /app/q.py publish <file>` — publish the directive in `<file>`.
  - `python3 /app/q.py survey` — re-run only the survey, overwriting
    `/app/roundtrip.out`.
- `/app/job.json` — a valid directive (per the Section 1 rules) that, when
  published, the worker accepts.
- `/app/roundtrip.out` — the single JSON line replied by `SURVE` for the
  nearest site on the active map.

The grader will re-run your tool against a fresh broker and a fresh gate
(including maps/directives you have not seen) and byte-check the receipts your
injection causes and the survey line you leave behind.