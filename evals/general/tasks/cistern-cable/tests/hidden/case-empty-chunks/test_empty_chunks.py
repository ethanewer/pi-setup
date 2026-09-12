"""Hidden case for cistern-cable: empty chunks inside the stream.

The upstream regression test streams only non-empty chunks.  This case feeds
the streaming path empty byte chunks interleaved with real ones, and a
completely empty stream.  Before the fix, TextChunker.decode('') returned
[''] so every empty decode (including the final decoder flush) surfaced as a
spurious empty text piece; after the fix only the real text pieces appear.
"""

import httpx


def test_interleaved_empty_chunks():
    response = httpx.Response(
        200, content=iter((b"", b"Hello", b"", b" world", b""))
    )
    parts = list(response.iter_text())
    assert parts == ["Hello", " world"]
    assert "" not in parts


def test_empty_stream_yields_nothing():
    response = httpx.Response(200, content=iter([]))
    parts = list(response.iter_text())
    assert parts == []


def test_empty_chunks_probe_script_contract():
    # Same shape as /app/probe_iter_text.py, but with interior empty chunks:
    # the probe must pass after the fix.
    import subprocess
    import sys

    script = "/app/probe_iter_text.py"
    result = subprocess.run([sys.executable, script], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr