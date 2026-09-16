#!/bin/bash
# Oracle for bracket-berth: applies the upstream-equivalent fix (a seen_data
# guard on the zstd decoder's flush()) to the real checkout at /app/src,
# proves the observable contract and keeps the upstream decoder suite green,
# then writes the /app/fix-report.md deliverable.
#
# This is the exact change upstream shipped (verified byte-identical to
# httpx commit 47f4a96's httpx/_decoders.py). It never reads test fixtures.
set -euo pipefail

# 1) The fix: an empty zstd body is not a truncated stream. Track whether any
#    data was ever fed; flush() of a data-less decoder is a no-op.
python3 - <<'PY'
from pathlib import Path

path = Path("/app/src/httpx/_decoders.py")
source = path.read_text()

source = source.replace(
    "        self.decompressor = zstandard.ZstdDecompressor().decompressobj()\n\n    def decode",
    "        self.decompressor = zstandard.ZstdDecompressor().decompressobj()\n        self.seen_data = False\n\n    def decode",
    1,
)
source = source.replace(
    "    def decode(self, data: bytes) -> bytes:\n        assert zstandard is not None\n        output = io.BytesIO()",
    "    def decode(self, data: bytes) -> bytes:\n        assert zstandard is not None\n        self.seen_data = True\n        output = io.BytesIO()",
    1,
)
source = source.replace(
    "    def flush(self) -> bytes:\n        ret = self.decompressor.flush()  # note: this is a no-op",
    "    def flush(self) -> bytes:\n        if not self.seen_data:\n            return b\"\"\n        ret = self.decompressor.flush()  # note: this is a no-op",
    1,
)
assert "self.seen_data" in source, "patch did not apply"
path.write_text(source)
print("patched /app/src/httpx/_decoders.py")
PY

# 2) The observable contract, end to end, in a fresh interpreter.
cd /app/src
python3 - <<'PY'
import asyncio
import httpx

# the reproducer from the task description
out = httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=b"").content
assert out == b"", out
print("repro: b''")

# reading paths on a zero-length zstd response
r = httpx.Response(200, headers=[(b"Content-Encoding", b"zstd")], content=b"")
assert r.read() == b""

# a real (mock-transport) client round-trip
def handler(request):
    return httpx.Response(200, headers={"Content-Encoding": "zstd"}, content=b"")

with httpx.Client(transport=httpx.MockTransport(handler)) as client:
    response = client.get("https://example.com/empty")
    assert response.content == b""
    assert list(response.iter_bytes()) == []

# async round-trip
async def ahandler(request):
    return httpx.Response(200, headers={"Content-Encoding": "zstd"}, content=b"")

async def main():
    async with httpx.AsyncClient(transport=httpx.MockTransport(ahandler)) as client:
        response = await client.get("https://example.com/empty")
        assert await response.aread() == b""
        assert [b async for b in response.aiter_bytes()] == []

asyncio.run(main())
print("observable contract ok")
PY

# 3) The project's own regression tests: the golden file extracted from the
#    upstream fix commit, and the pre-existing decoder suite on the tree.
python3 -m pytest -q -p no:cacheprovider /opt/golden/test_decoders.py
python3 -m pytest -q -p no:cacheprovider tests/test_decoders.py

# 4) The deliverable report.
cat > /app/fix-report.md <<'MD'
# Fix report: zstd-decoding a zero-length response body

**Where the fault lives:** `/app/src/httpx/_decoders.py`, in
`ZStandardDecoder` — specifically its `flush()` step. When a response with
`Content-Encoding: zstd` has an empty body, `flush()` is the only decoder
step that runs, and it unconditionally consulted the underlying
decompressor's `eof` flag: with nothing ever fed, `eof` is false, so the
decoder raised `DecodingError("Zstandard data is incomplete")` even though
the server deliberately sent zero bytes. An empty body is not a truncated
stream.

**The change:** track whether any data has ever been fed to the decoder
(`self.seen_data`, set in `decode()`), and have `flush()` return `b""`
immediately when no data was ever seen. Truncated streams (data was fed but
the stream never reached EOF) still raise `DecodingError` exactly as before.

**Verification:**
- the task reproducer now prints `b''` and exits 0;
- `.content`, `.read()`, `.iter_bytes()` and the `httpx.Client` /
  `httpx.AsyncClient` round-trip paths all return an empty byte string for
  the zero-length zstd response without raising;
- the upstream regression tests (including the golden empty/truncated pair)
  and the pre-existing `tests/test_decoders.py` all pass.
MD

# 5) Sanity: report and tree state (no fixtures involved).
[ -s /app/fix-report.md ]
grep -q "/app/src/httpx/_decoders.py" /app/fix-report.md
cd /app/src && git status --porcelain
echo "bracket-berth oracle done"