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

NOTE: this shipped build deliberately contains a RACE CONDITION (seeded
bug).  The per-request merge at the bottom of process_request() performs a
non-atomic read-modify-write for every counter: it reads the shared dict
entry, then awaits the simulated slow I/O step, then writes the updated
count back.  Concurrent requests therefore interleave inside the update and
drop increments (lost updates) — the aggregation silently undercounts under
load.
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
        # RACE: for each counter the update reads the shared dict entry,
        for word, inc in doc_tally.items():
            old = self.counts.get(word, 0)
            await asyncio.sleep(self.io_latency)  # simulated slow I/O step
            self.counts[word] = old + inc
        # then awaits the slow I/O step, then writes the update back — the
        # read-modify-write spans an await, so concurrent requests read the
        # same stale entry and clobber each other's increments.
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