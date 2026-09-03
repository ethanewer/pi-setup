"""httpkit - a self-contained mini HTTP client library.

Ships with a request builder and a response parser that support simple
requests and Content-Length framing only.  The task extends it with:

- multipart.py: multipart/form-data body building (exact bytes),
- chunked.py:   chunked transfer-encoding decoding (with trailers),
- cookies.py:   a deterministic cookie store (parsing, scoping,
                eviction, header assembly).

Standard library only; everything operates on bytes and callables, no
network access.
"""

__version__ = "0.1.0"