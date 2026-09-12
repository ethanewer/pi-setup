#!/usr/bin/env python3
"""Probe: can a requests JSONDecodeError survive a pickle round-trip?

This checkout is the requests library with a real upstream bug: an error
raised for invalid JSON cannot be pickled and then unpickled. A
multiprocessing process pool hits exactly this when a worker fails on
malformed JSON, because the pool pickles the worker exception to re-raise it
in the parent process.
"""

import pickle

from requests.exceptions import JSONDecodeError

doc = '{"responseCode":["706"]}{"responseCode":["706"]}'
error = JSONDecodeError("Extra data", doc, 36)
print("original repr:", repr(error))
print("msg/doc/pos :", error.msg, "|", repr(error.doc), "|", error.pos)

try:
    round_tripped = pickle.loads(pickle.dumps(error))
except TypeError as exc:
    print("PICKLE ROUND-TRIP FAILED:", exc)
else:
    print("round-trip repr:", repr(round_tripped))
    print("SAME REPR:", repr(error) == repr(round_tripped))