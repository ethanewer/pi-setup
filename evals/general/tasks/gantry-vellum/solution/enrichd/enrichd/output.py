"""Append-only line-serialised output sink."""
import json
import os


class OutputSink:
    """Writes one JSON object per line to a file, flushing periodically."""

    def __init__(self, path, flush_every=8):
        self.path = path
        self.flush_every = max(1, flush_every)
        self.fh = None
        self.written = 0

    def __enter__(self):
        parent = os.path.dirname(self.path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        self.fh = open(self.path, "w", encoding="utf-8", buffering=1)
        return self

    def write(self, obj):
        self.fh.write(json.dumps(obj, separators=(",", ":")) + "\n")
        self.written += 1
        if self.written % self.flush_every == 0:
            self.fh.flush()

    def __exit__(self, exc_type, exc, tb):
        if self.fh is not None:
            self.fh.flush()
            self.fh.close()
        return False
