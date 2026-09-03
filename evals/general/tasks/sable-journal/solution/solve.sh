#!/bin/bash
#
# sable-journal oracle. Does the real work from a pristine container:
#   1. authors the root-cause writeup /app/diagnosis.md (naming the exact
#      read/await/write lines of the SHIPPED buggy file: 59, 60, 61);
#   2. repairs the shipped service in place: /app/svc/wordcount_service.py
#      becomes the fixed build (the merge is one synchronous critical
#      section — no await between reading a counter and writing it back);
#   3. smoke-tests the repair under the documented load: the sequential
#      ground-truth run (1 worker) and the concurrent run (40 workers) must
#      produce identical counts.
# Never reads /tests.
set -euo pipefail

# ---- 1. /app/diagnosis.md (root cause, exact lines, interleaving, fix class)
cat > /app/diagnosis.md <<'MDEOF'
# sable-journal — root-cause diagnosis

## Bug: lost updates in the shared word-count dict (non-atomic read-modify-write)

File: /app/svc/wordcount_service.py (as shipped; byte-identical reference at
/opt/pristine/wordcount_service.py).

The seeded race lives in `WordCountService.process_request()`, in the merge
loop that folds a document's tally into the shared `self.counts` dict:

    line 59:  old = self.counts.get(word, 0)          <- READ shared entry
    line 60:  await asyncio.sleep(self.io_latency)    # simulated slow I/O
    line 61:  self.counts[word] = old + inc           <- WRITE back

## Interleaving that corrupts the counts

Every request's merge does read -> await -> write per word, with no guarantee
the read and the write-back are adjacent. asyncio is cooperative: the moment
a handler hits the await at line 60 the event loop freely runs any other
in-flight request. Under the documented load (40 concurrent workers driving
loopback requests), many requests read the same STALE entry (e.g. every
worker reads 0 for "bracken" before anyone writes), then each writes `old +
inc`. Only the last writer survives; every other increment for that word is
silently LOST, so the final aggregation undercounts. The corruption is
deterministic in kind (lost updates) though not in exact value.

## Fix class

Make the merge a synchronous critical section: read and write each counter
back-to-back with NO AWAIT in between, so the event loop can never
interleave a second request inside the read-modify-write. The simulated slow
I/O step stays, but outside the merge. An asyncio.Lock guarding the merge is
the equivalent class of fix.
MDEOF

# ---- 2. /app/svc/wordcount_service.py — repaired in place (atomic merge)
cat > /app/svc/wordcount_service.py <<'PYEOF'
#!/usr/bin/env python3
"""wordcount_service.py — asyncio word-count aggregation service.

A minimal HTTP-flavored request service bound to 127.0.0.1 (loopback only).
One request per line, ASCII, CRLF-terminated:

    GET /req/<doc_id> HTTP/1.0     tally document <doc_id> into the shared
                                   running counts; response body "OK"
    GET /dump HTTP/1.0             response body = JSON object of the
                                   running counts
    GET /stop HTTP/1.0             response body "BYE", then clean shutdown

The corpus file (--corpus, e.g. /app/data/corpus.txt) is plain text with one
document per line; document i is line i (0-based).  A request for document d
tallies every lowercase, whitespace-separated token of line d into the shared
counts dict (each occurrence contributes +1).

REPAIR: the merge into the shared counts is a single synchronous critical
section.  Each counter's read and write-back happen back-to-back with no
await in between, so the event loop can never interleave a second request
inside the read-modify-write; lost updates are impossible.  The simulated
slow I/O step (the document read) happens before the merge and does not
touch the shared dict.
"""
import argparse
import asyncio
import json
import sys


class WordCountService:
    """Aggregates per-token counts of the documents requested over the wire."""

    def __init__(self, corpus_path, io_latency=0.001):
        with open(corpus_path, "r", encoding="utf-8") as fh:
            self.docs = fh.read().splitlines()
        self.io_latency = io_latency
        self.counts = {}

    @staticmethod
    def tally_text(text):
        tally = {}
        for token in text.lower().split():
            tally[token] = tally.get(token, 0) + 1
        return tally

    async def process_request(self, doc_id):
        """Tally one document into the shared counts; returns token total."""
        # Simulated slow I/O step: pretend the document is read from disk.
        text = self.docs[doc_id]
        await asyncio.sleep(self.io_latency)

        doc_tally = self.tally_text(text)

        # ---- merge into the shared counts ------------------------------
        # One synchronous critical section: read and write-back are
        # adjacent with no await between them, so no other request can
        # interleave inside the read-modify-write.
        for word, inc in doc_tally.items():
            self.counts[word] = self.counts.get(word, 0) + inc
        return sum(doc_tally.values())

    async def handle_connection(self, reader, writer):
        stop = False
        try:
            while not stop:
                line = await reader.readline()
                if not line:
                    break
                req = line.decode("ascii", "replace").strip()
                if not req:
                    continue
                if req.startswith("GET /req/"):
                    doc_id = int(req.split()[1][len("/req/"):])
                    await self.process_request(doc_id)
                    resp_body = "OK"
                elif req.startswith("GET /dump"):
                    resp_body = json.dumps(self.counts)
                elif req.startswith("GET /stop"):
                    resp_body = "BYE"
                    stop = True
                else:
                    resp_body = "BAD"
                body = resp_body.encode("utf-8")
                writer.write(
                    b"HTTP/1.1 200 OK\r\nContent-Length: "
                    + str(len(body)).encode()
                    + b"\r\n\r\n"
                    + body
                )
                await writer.drain()
        except Exception:
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass
        return stop


async def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--io-latency", type=float, default=0.001)
    args = parser.parse_args(argv)

    service = WordCountService(args.corpus, args.io_latency)
    shutdown = asyncio.Event()

    async def on_connect(reader, writer):
        if await service.handle_connection(reader, writer):
            shutdown.set()

    server = await asyncio.start_server(on_connect, "127.0.0.1", args.port)
    print("READY", flush=True)
    try:
        await shutdown.wait()
    finally:
        server.close()
        await server.wait_closed()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
PYEOF

chmod 0755 /app/svc/wordcount_service.py

# ---- 3. Smoke test: concurrent documented-load run equals the sequential
#           ground-truth run for the repaired service.
python3 - <<'PY'
import json
import subprocess
import sys


def run_lg(workers, requests):
    out = "/tmp/tl_oracle_%d_%d.json" % (workers, requests)
    cmd = [
        sys.executable, "/app/svc/loadgen.py",
        "--service", "/app/svc/wordcount_service.py",
        "--corpus", "/app/data/corpus.txt",
        "--workers", str(workers), "--requests", str(requests),
        "--seed", "2718",
        "--port", str(8600 + workers),
        "--out", out,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if res.returncode != 0:
        print("oracle loadgen failed: %s" % res.stderr[-500:], file=sys.stderr)
        sys.exit(1)
    with open(out, "r", encoding="utf-8") as fh:
        return json.load(fh)


truth = run_lg(1, 240)     # sequential -> exact counts
fixed = run_lg(40, 6)      # documented concurrent load
if truth != fixed:
    print("oracle smoke: counts diverge under documented load", file=sys.stderr)
    sys.exit(1)
print("oracle smoke OK: %d distinct words, exact under documented load" % len(fixed))
PY

echo "solve.sh done: /app/diagnosis.md + repaired /app/svc/wordcount_service.py"