# Close status 1006 on the wire must be a protocol violation

## Situation

`/app/src` is a shallow, pinned checkout of the aiohttp project
(`https://github.com/aio-libs/aiohttp`), checked out at upstream commit
`14a1b5427213b5b982922627a44e4c5ae23bc0e3`, and installed from that tree in
editable (development) mode with the C extensions disabled, so the code you
import is exactly the checked-out Python source. Python 3.12, pytest, and the
pytest plugins the project's own test configuration needs are installed, and
everything the task needs is already in the image. `/opt/golden`, `/tests`
and `/solution` are harness-owned; do not touch them. `/app/hints.md` may
help.

## The bug (user-visible symptom)

A WebSocket peer closes the connection with status code `1006`. Per
RFC 6455 section 7.4.1 that code is reserved: it must never appear on the
wire (1004, 1005, 1006 and 1015 are all forbidden there). 1006 is special
because aiohttp itself uses it internally to signal an abnormal connection
drop and exports it as `WSCloseCode.ABNORMAL_CLOSURE`; the other three
reserved codes are not members of that enum.

In this checkout the peer's Close frame is accepted as a normal close:
aiohttp's WebSocket reader surfaces close code `1006` to the application
instead of flagging a protocol violation. Codes `1004`, `1005` and `1015`
are already rejected with a protocol error; only `1006` is wrongly accepted.

The desired behaviour:

- a Close frame whose status code is `1006` must raise
  `aiohttp.http.WebSocketError` with code `WSCloseCode.PROTOCOL_ERROR`
  (value 1002);
- rejection of the other reserved codes `1004`, `1005`, `1015` must keep
  working unchanged;
- every status code that is valid on the wire -- the RFC 6455 codes
  `1000`-`1014` other than `1006`, and the private-use codes `3000`-`4999`
  -- must still be accepted, with the reported code preserved.

## Deliverable 1: `/app/reproduce_issue.py` (write this before fixing anything)

Write a standalone Python 3 script at `/app/reproduce_issue.py` that
exercises aiohttp's WebSocket frame reader directly: build a raw Close frame
carrying status `1006` yourself (RFC 6455 framing: `0x88` as the first byte,
then the length, then the 2-byte big-endian unsigned status code) and feed it
to the real reader, the same way the project's own parser tests construct and
feed frames.

Contract:

- exit status `0` and a final line starting with `RESULT: PASS` exactly when
  the reader raises a protocol error for status `1006`;
- exit status non-zero (and no `RESULT: PASS` line) while the bug is present;
- the script must build the frame and feed it to the reader itself -- no
  stubs, no fakes, no reading source text or bytecode.

The verifier runs your script twice from the same working directory against
one clean materialization of your tree that differs only in whether your
change is present: once with your change (must exit 0 with
`RESULT: PASS`), and once at the pinned commit with the agent-side change
reverted (must exit non-zero). A script that always passes, that does not
actually drive the reader, or that detects its surroundings instead of the
bug, fails the verifier.

## Deliverable 2: the repaired `/app/src` tree

Fix the bug in the checked-out tree, in place, with the bare minimum edit
surface, and drive your work with the project's own test runner from
`/app/src`:

```
cd /app/src && python3 -m pytest tests/test_websocket_parser.py -q -p no:cacheprovider
```

The whole existing parser test file is green at the pinned commit; keep it
green. The verifier additionally runs the project's own writer tests.

## Constraints

- The checkout must stay at the pinned commit: the verifier asserts that
  `HEAD` is still `14a1b5427213b5b982922627a44e4c5ae23bc0e3` and that the
  upstream fix commit is not reachable in `/app/src`. Do not fetch, add
  remotes, rewrite history, or apply upstream patches.
- Change only what the fix requires, in one tracked file: the verifier
  requires the tracked working tree to differ from the pinned commit in
  exactly one source file, and forbids new files inside the aiohttp package
  and any change to build files.
- Do not modify anything under `/opt/golden`, `/tests` or `/solution`; do not
  add files to the source tree -- your reproduction belongs in `/app`.
- The C extensions are disabled in this image by design; the reader under
  test is the pure-Python one and the verifier checks that explicitly.

## What the verifier checks (summary)

1. Tree integrity: `HEAD` pinned, upstream fix commit unreachable, exactly
   one tracked source file modified, no new files inside the aiohttp
   package.
2. Your `/app/reproduce_issue.py` exits 0 with `RESULT: PASS` on the
   repaired tree and fails on the pre-fix tree.
3. The project's own regression test for this behaviour passes (extracted
   from upstream into `/opt/golden` at image build time).
4. The project's own existing websocket parser and writer tests still pass.
5. Hidden cases over inputs the upstream regression test does not use:
   masked (client-to-server) Close frames and extended 16-bit-length frames
   carrying `1006` are still rejected; a `1006` status split across chunks
   is still rejected; and a guard that the valid codes `1000`-`1014` (other
   than 1006) and `3000`-`4999` remain accepted.

Deliverables: the repaired `/app/src` tree and `/app/reproduce_issue.py`.