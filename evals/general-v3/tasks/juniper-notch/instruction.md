# Juniper Notch Relay Station — bring the relay online

You are the relay operator for **juniper-notch-77**, a telemetry relay sitting
on a mountain notch. The station carries two kinds of traffic over its
loopback port:

1. a **job bus** — an **unauthenticated MQTT** message queue that a relay worker
   drains; and
2. a **survey gate** — a raw TCP text service that answers structured map/site
   requests.

Your job is to (a) craft a task directive and **inject it into the queue the
worker consumes**, and (b) **drive the survey-gate socket protocol** to capture
a site reply. Everything you need to know about the endpoints and their
wire formats is discoverable *inside the container* from:

- `/app/relay/station.toml` — the relay's own config: where the bus and the
  gate live, what topic the worker views, and whether the bus needs
  credentials (it does not).
- `/app/relay/README.md` — the operator manual describing both protocols.
- `/app/relay/worker.py` and `/app/relay/gate.py` — the actual fixtures; read
  them to learn the exact message shapes and commands they accept.

Do **not** modify the relay fixtures (`/app/relay/worker.py`,
`/app/relay/gate.py`, `station.toml`, `broker.conf`, or anything under
`/app/relay/maps/`). They are the services your work must interoperate with.
`paho-mqtt`, `aiohttp` and `numpy` are already installed.

---

## Deliverables (all under `/app`, all required)

| Path | What it must be |
|------|-----------------|
| `/app/q.py` | Your relay tool (a working Python program). |
| `/app/job.json` | A **valid** task directive (exact schema below) that, once published, the worker accepts. |
| `/app/roundtrip.out` | The **SURVE** site reply line for the **active** map (single JSON line). |

`python3 /app/q.py` (no arguments) must do two things, in this order:

1. Read the directive in `/app/job.json` and **publish it** (retain=true) to
   the worker's inbox topic on the bus.
2. Query the survey gate, select the correct site, and write that site's
   **SURVE reply** to `/app/roundtrip.out`.

Your tool must also support two modes the grader will invoke on inputs you
have not seen:

- `python3 /app/q.py publish <file>` — read the directive in `<file>` and
  publish it exactly as given (retain=true), byte-faithful to `<file>`.
- `python3 /app/q.py survey` — re-run only the survey and overwrite
  `/app/roundtrip.out`.

(Read `/app/relay/README.md` — it spells out a working skeleton for both the
MQTT client and the socket client.)

---

## 1. The job bus — inject a task the worker consumes

The bus is MQTT v3.1.1. It is **unauthenticated** (no username/password) and
runs on loopback at the address in `[bus]` of `station.toml`. A publisher
connects anonymously and publishes a JSON **directive** to the worker's inbox
topic with **retain=true** so a worker that subscribes later still receives it.

### The worker's directive schema (`/app/relay/worker.py`)

```json
{
  "job_id": "some-token",
  "kind":   "rebalance",
  "sector": "north",
  "payload": [3, 1, 4, 1, 5]
}
```

The worker enforces **all** of these rules; a directive that breaks any one of
them is ignored (no receipt) and does not disturb the worker:

- `job_id` — non-empty string of `[A-Za-z0-9_-]`, at most 64 chars.
- `kind` — must be exactly the string `"rebalance"`.
- `sector` — one of `"north"`, `"south"`, `"east"`, `"west"`.
- `payload` — a JSON array of **1 to 12 integers**, each `0..100000`; no
  booleans, no floats.

When a directive validates, the worker writes a receipt to
`/app/relay/applied/<job_id>.result.json` containing the applied values and a
deterministic digest of the directive. A malformed directive produces **no**
receipt and must never crash the worker.

**`/app/job.json` must satisfy every rule above.** Inject it so the worker
actually consumes it (a later-subscribing worker must still see it — use
retain=true). Crafting a directive that is rejected, or publishing to the wrong
topic/endpoint, means the worker never receives your task.

## 2. The survey gate — drive the socket request/response protocol

The gate is a raw TCP text server on loopback at `[gate]` in `station.toml`
(see `/app/relay/gate.py`). One connection: write a single command line, read a
single JSON response line, and (for a survey) send one follow-up on the same
connection.

- `MAP` → `{"ok":true,"kind":"map","target":{"row":R,"col":C},"sites":[{ "name":..., "row":R, "col":C }, ...]}`
- `SURVE <siteName>` → for a name present in the map:
  `{"ok":true,"kind":"site","site":"<name>","row":R,"col":C,"token":"<40hex>"}`.
  Unknown names return `{"ok":false,...}`.

To produce `/app/roundtrip.out`:

1. Connect to the gate, send `MAP`, and read the map plus its `target`.
2. Choose the site whose `(row,col)` is nearest to `target` by **Manhattan
   distance** `|row−targetRow| + |col−targetCol|`. **Ties**: pick the
   lexicographically smallest site name.
3. Send `SURVE <thatSite>` and read the reply.
4. Write your selected site's **SURVE reply** to `/app/roundtrip.out` as a
   single JSON line (the exact `{"ok":true,"kind":"site",...}` object).

`/app/roundtrip.out` must reflect the map currently served by the **active**
gate — it must be computed live, not hardcoded.

---

## Edge cases the grader will exercise (implement them correctly)

The grader boots a **fresh unauthenticated broker and a fresh gate**, executes
your tool, and checks:

1. **Unseen valid directive** — the grader calls
   `python3 /app/q.py publish <unseen_valid.json>` where the directive uses a
   *different* `sector` and a *different* `payload` you have never seen. Your
   tool must publish it faithfully and the worker must consume it (producing a
   receipt whose digest matches a deterministic recomputation). This proves
   your injection is not hardcoded for `/app/job.json`.
2. **Unseen map** — the grader restarts the gate on a *different* map (a
   different `target`, different site set, and at least one **nearest-site
   tie**) and calls `python3 /app/q.py survey`. Your surveyed site + token must
   match a live recomputation. This proves `/app/roundtrip.out` is computed, not
   a canned answer.
3. **Malformed directive** — the grader calls
   `python3 /app/q.py publish <malformed.json>` where the directive violates
   the schema (e.g. a `kind` that is not `"rebalance"`). Your tool publishes it
   as given; the worker must **reject** it (no receipt) and **stay alive**.
4. **Default run** — `python3 /app/q.py` must publish `/app/job.json` and
   produce a correct `/app/roundtrip.out` for the default map.

The three deliverables must survive all of the above. Any mismatch → 0.

## Constraints

- Work only inside the container. `/tests` and `/solution` are not available
  to you (do not attempt to read them).
- Do not modify the relay fixtures. Your changes must be confined to
  `/app/q.py`, `/app/job.json`, and `/app/roundtrip.out`.
- The relay is unauthenticated and loopback-only; that is the intended design.
- The grader validates your deliverables byte/precisely and re-runs your tool
  on unseen inputs, so make `/app/q.py` robust and idempotent.
