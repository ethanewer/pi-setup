#!/usr/bin/env python3
"""Ridgeor queue consumer worker.

A tiny local "broker consumer" that receives one binary serialized message
(e.g. a routed topic payload) and deserializes it with pickle.load().  It is the
consuming worker named in the ops runbook: a message that arrives on the
ingestion topic is unpacked here exactly as an operator would unwind it.

Usage:
    python3 worker.py [payload.pkl]

When handed a hostile message, unpickling runs the command encoded by the
payload, recreating the documented failure mode (arbitrary command execution).
"""

import pickle
import sys

PAYLOAD = "/app/message.pkl"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else PAYLOAD
    with open(path, "rb") as fh:
        obj = pickle.load(fh)
    print("deserialized message: %r" % (obj,))


if __name__ == "__main__":
    main()