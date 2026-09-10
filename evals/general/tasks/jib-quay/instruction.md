# jib-quay — repair the transfer-hub deadlock

The container runs **quay-hub**, a threaded FX transfer service. Under a
specific concurrent load the service **hangs**: requests stop being answered
and it never recovers. Your job is to reproduce the hang, root-cause it,
repair the service in place, and write the diagnosis that explains it.

## Environment

| Path | What it is |
|---|---|
| `/app/service.py` | the transfer hub, **shipped with a seeded concurrency defect** |
| `/app/driver.py` | deterministic load driver: starts the service, drives a mix, detects stalls |
| `/app/ledger.json` | visible ledger: accounts and FX rates |
| `/app/mix_visible.json` | the visible operation mix (3 workers, 12 transfers) |
| `/opt/pristine/` | byte-identical reference copies used ONLY by the grader — never modify anything under `/opt` |

Python standard library only. Loopback (`127.0.0.1`) only; there is no other
network access. Keep everything deterministic — no randomness and no
wall-clock dependence as part of the answer.

## Multiple copies of the same two files

The grader keeps its own byte-identical copies of the shipped service and of
the fixtures and re-runs them independently. Editing or deleting a fixture,
the driver, or a pristine copy to make the problem go away cannot help.

## quay-hub: how it works

Launch the service with:

```
python3 /app/service.py --port PORT --ledger LEDGER [--latency SEC]
```

It prints one line `READY` on stdout once listening, then speaks a minimal
line protocol on `127.0.0.1:PORT` (one request per line, LF-terminated,
ASCII):

| Request | Response |
|---|---|
| `TRANSFER <src> <dst> <cents>` | `OK <converted>` on success, or `NOACCT` (unknown account), `NOFUNDS` (insufficient balance), `BAD` (non-positive/non-numeric amount or `src == dst`) |
| `BALANCE <account>` | `OK <balance_cents>`, or `NOACCT` |
| `JOURNAL` | `OK <json-line>` — the ordered list of applied transfers |
| `STOP` | `BYE`, then the process exits 0 |
| anything else | `BAD` |

**Transfer semantics (exact).** A transfer of `<cents>` from `<src>` to
`<dst>` applies only if `<src>` holds at least `<cents>` at apply time.
`<src>` is debited `<cents>` in its own currency; `<dst>` is credited
`round(<cents> * rate(src.currency, dst.currency))` cents in its own currency,
where `rate` looks up the pair string `"<CCY>-<CCY>"` in the ledger's `rates`
table and defaults to `1.0` when the pair is absent. Every applied transfer
is appended to the in-memory journal as:

```
{"src": "<account>", "dst": "<account>", "cents": <int>, "converted": <int>}
```

Every transfer also includes a simulated **FX rate-feed latency step** of
`--latency` seconds; the grader passes `--latency` itself and verifies the
step is still honored, so deleting or drastically shortening it is not a
valid fix.

The ledger (`--ledger`) JSON schema:

```json
{
  "accounts": {"<id>": {"balance_cents": <int>, "currency": "<CCY>"}, ...},
  "rates":    {"<CCY>-<CCY>": <float>, ...}
}
```

## The load driver

```
python3 /app/driver.py --service /app/service.py --ledger LEDGER \
    --mix MIX --port PORT --out OUT.json [--serial] [--latency SEC]
    [--gap SEC] [--deadline SEC]
```

Mix schema:

```json
{
  "workers": 3,
  "ops": [ {"op": "transfer", "src": "alice", "dst": "bob", "cents": 12000}, ... ]
}
```

Driver semantics:

- concurrent mode (default): `workers` client connections are opened and
  released together at a start barrier; worker `w` sends ops
  `w, w+workers, w+2*workers, ...` (round-robin) and reads each response
  before sending the next;
- `--serial`: a single connection sends every op in list order;
- a run that stops receiving responses while ops are still outstanding is a
  **stall**; the driver aborts, kills the service, writes
  `{"ok": false, "stall": true, ...}` to `--out` and exits 1;
- a completed run writes `ok: true` with `elapsed` (barrier-to-last-response
  seconds), the per-op `responses`, the service `journal`, and per-account
  `balances`.

## Reproduce the bug

1. **Serial ground truth** — one connection serializes everything and the
   shipped service completes:

   ```
   python3 /app/driver.py --service /app/service.py --ledger /app/ledger.json \
       --mix /app/mix_visible.json --port 8765 --serial --out /tmp/serial.json
   ```
   Expect exit 0, 12/12 responses.

2. **Documented concurrent load** — the same 12 transfers split across the
   mix's 3 clients hang the shipped service:

   ```
   python3 /app/driver.py --service /app/service.py --ledger /app/ledger.json \
       --mix /app/mix_visible.json --port 8766 --out /tmp/concurrent.json
   ```
   Expect a stall: response flow stops after a couple of transfers and
   nothing further is ever answered, exit 1.

That stall — permanent, blocking even later requests — is the defect this
task is about. Find out why the interleaving produces it, then repair
`/app/service.py` so **every** concurrent run completes with exact results
while the service keeps serving requests concurrently.

## Deliverables (both required)

1. **`/app/service.py`** — repaired **in place**. Keep the CLI
   (`--port`, `--ledger`, `--latency`), the `READY` line, the protocol, the
   conversion formula, and the loopback-only behavior identical.

2. **`/app/diagnosis.md`** — the root-cause writeup. It must:
   - record how you reproduced it (the commands and what you observed);
   - name the two operations that can interleave and block each other
     permanently, and the exact code region where the blocking happens
     (function and lines of the shipped file — the pristine copy at
     `/opt/pristine/service.py` preserves the original line numbers);
   - explain the interleaving: who holds what, who waits for what, and why
     neither side can ever proceed;
   - state the fix class you applied and why it removes the hang while
     preserving concurrent throughput.

## How the grader probes the result

- It runs **its own** stress harness against your `/app/service.py`, with
  **3 hidden operation mixes** (different accounts, currencies, rates,
  worker counts — none visible to you), **10 concurrent runs of each**, each
  bounded in time. Any run that fails to complete is a failure.
- It independently recomputes the expected outcome of each mix from the
  ledger and the exact semantics above: the journal must be exactly the
  mix's transfers (every one applied exactly once, nothing missing, nothing
  duplicated), every `converted` amount must equal
  `int(round(cents * rate(...)))`, and every account's reported balance must
  equal the deterministic replay of those transfers from the initial
  ledger.
- It re-runs the **original** shipped service (its own pristine copy) under
  the same hidden mixes and requires the hang to still reproduce — this is
  the proof the seeded defect is real and your repair is what fixed it.
- It verifies the `--latency` FX step still takes honest time.
- It measures a **concurrency floor**: the best concurrent run must finish
  well under the best serial run of the same mix. A fix that collapses the
  service onto one global lock, or onto a single connection-handling
  thread, serializes every transfer and fails this gate.
- It checks `/app/diagnosis.md` describes the deadlock (operation
  interleaving, code region, fix class).

## Constraints

- Python stdlib only; no third-party imports.
- Do not modify `/app/ledger.json`, `/app/mix_visible.json`,
  `/app/driver.py`, or anything under `/opt/pristine/` — the grader
  hash-checks all of them.
- Keep the `--latency` semantics; the grader supplies its own value and
  measures it.
- Keep the service genuinely concurrent per the concurrency floor above.
- The whole grader cycle must stay fast: one hidden-case run of the fixed
  service completes in well under a second.