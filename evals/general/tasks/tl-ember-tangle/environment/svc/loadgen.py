#!/usr/bin/env python3
"""loadgen.py — deterministic concurrent load generator.

Spawns the word-count service as a subprocess, drives ((--requests) per
worker, --workers workers) requests through loopback HTTP, and writes the
service's final aggregated counts to --out as a JSON object (word -> total).

Determinism: the request schedule is a pure function of
(--workers, --requests, --seed, corpus line count).  With
rng = random.Random(seed), global request index k (0 <= k < workers*requests)
draws document rng.randrange(num_docs), where num_docs is the number of
lines in the corpus file.  Worker w sends request indices k = w, w+N, w+2N,
... (round-robin).  The same arguments always produce the same schedule and
therefore the same true counts.

Exit code 0 only when: the service became ready, every request was answered
with HTTP/1.1 200 and body "OK", the dump parsed, the service shut down
cleanly, and the result was written to --out.
"""
import argparse
import asyncio
import json
import random
import subprocess
import sys
import time


async def read_http_response(reader):
    """Read one HTTP/1.x response: status line, headers, then body."""
    status_line = await reader.readline()
    headers = []
    length = 0
    while True:
        line = await reader.readline()
        if line in (b"\r\n", b"\n", b""):
            break
        headers.append(line.decode("ascii", "replace").strip())
    for h in headers:
        if h.lower().startswith("content-length:"):
            length = int(h.split(":", 1)[1].strip())
    body = b""
    if length:
        body = await reader.readexactly(length)
    parts = status_line.decode("ascii", "replace").split()
    status = parts[1] if len(parts) > 1 else "?"
    return status, body


async def send_request(port, path, expect_body):
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    try:
        writer.write(("GET %s HTTP/1.0\r\n\r\n" % path).encode("ascii"))
        await writer.drain()
        status, body = await read_http_response(reader)
        if status != "200":
            raise RuntimeError("GET %s -> status %s" % (path, status))
        if expect_body is not None and body != expect_body:
            raise RuntimeError("GET %s -> unexpected body %r" % (path, body))
        return body
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


async def worker(port, doc_ids):
    """One worker connection: tally each assigned document, read the reply."""
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    try:
        for doc_id in doc_ids:
            path = "/req/%d" % doc_id
            writer.write(("GET %s HTTP/1.0\r\n\r\n" % path).encode("ascii"))
            await writer.drain()
            status, body = await read_http_response(reader)
            if status != "200" or body != b"OK":
                raise RuntimeError("GET %s -> %s %r" % (path, status, body))
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


async def main():
    ap = argparse.ArgumentParser(
        prog="loadgen",
        description="Deterministic concurrent load generator for the "
                    "wordcount service.",
    )
    ap.add_argument("--service", required=True, help="service base URL")
    ap.add_argument("--corpus", required=True, help="input corpus file")
    ap.add_argument("--workers", type=int, required=True,
                    help="number of concurrent workers")
    ap.add_argument("--requests", type=int, required=True,
                    help="requests per worker")
    ap.add_argument("--seed", type=int, required=True,
                    help="seed for the deterministic request schedule")
    ap.add_argument("--port", type=int, required=True, help="service port")
    ap.add_argument("--out", required=True, help="output file path")
    args = ap.parse_args()

    with open(args.corpus, "r", encoding="utf-8") as fh:
        num_docs = len(fh.read().splitlines())
    total = args.workers * args.requests
    rng = random.Random(args.seed)
    schedule = [rng.randrange(num_docs) for _ in range(total)]

    proc = subprocess.Popen(
        [sys.executable, args.service,
         "--port", str(args.port), "--corpus", args.corpus],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        deadline = time.monotonic() + 30.0
        ready = False
        while time.monotonic() < deadline:
            line = proc.stdout.readline()
            if not line:
                break
            if line.strip() == b"READY":
                ready = True
                break
        if not ready:
            raise RuntimeError("service did not become ready (port %d)" % args.port)

        worker_lists = [schedule[w::args.workers] for w in range(args.workers)]
        await asyncio.gather(*(worker(args.port, wl) for wl in worker_lists))

        body = await send_request(args.port, "/dump", None)
        counts = json.loads(body.decode("utf-8"))

        await send_request(args.port, "/stop", b"BYE")
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()

    if proc.returncode != 0:
        print("loadgen: service exited with %d" % proc.returncode, file=sys.stderr)
        err = (proc.stderr.read() if proc.stderr else b"").decode("utf-8", "replace")
        if err:
            print(err[-500:], file=sys.stderr)
        sys.exit(1)

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(counts, fh)
    print("LOADGEN_OK docs=%d total-requests=%d" % (num_docs, total))


if __name__ == "__main__":
    asyncio.run(main())