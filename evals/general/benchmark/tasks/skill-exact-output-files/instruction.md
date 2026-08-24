# Exact output file

Create a file `/app/exact.bin` whose byte content is **exactly** the byte
sequence described below — byte-for-byte, with nothing added and nothing
removed, no trailing newline.

The required byte sequence, given as a hex string (2 hex digits per byte,
lowercase):

```
65786163742d6f757470757400ff01ff0a4142
```

Write a Python 3 script `/app/make_exact.py` that:

1. decodes the hex string above into bytes,
2. writes those exact bytes to `/app/exact.bin`.

Then run `/app/make_exact.py` so the file exists.

The verifier compares `/app/exact.bin` byte-for-byte against the expected
sequence above. Every byte must match exactly (including the embedded `00`
and `ff` bytes and the trailing newline `0a`).