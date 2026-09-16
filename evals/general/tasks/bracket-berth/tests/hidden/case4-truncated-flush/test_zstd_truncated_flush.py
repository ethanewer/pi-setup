"""Hidden case 4: a zstd stream truncated in its *tail*.

The frame header and payload are valid; only the trailing bytes (the
end-of-frame segment) are missing. The zstd library buffers such input
silently — decompress() returns partial bytes and raises nothing — so the
incompleteness is detectable only at the decoder's flush() step, via the
`eof` flag on the decompressor.

Measured against zstandard 0.25.0 in this image: for every cut tried
(1 byte off the end, 5 bytes off, half a frame) decompressobj.decompress()
returns b''-or-partial and raises nothing; then eof is False and
flush() is the only place that can still raise httpx.DecodingError.

Why this case exists: the upstream regression test for truncation
(test_zstd_truncated) feeds a stream whose *magic bytes* are broken, which
the zstd library rejects inside decode(). This case feeds a stream whose tail
is broken, which decode() passes through. A fake fix that silences flush()
altogether (so the empty-body repro prints b'') passes test_zstd_truncated
but must FAIL here — the empty body and the tail-truncated stream are
different inputs that the decoder must distinguish.
"""

import zstandard as zstd

import httpx


def _assert_decoding_error(content: bytes, label: str) -> None:
    # httpx.Response(...) materialises the body eagerly in __init__, so the
    # constructor itself may raise; the assertion must cover both stages.
    try:
        httpx.Response(
            200, headers=[(b"Content-Encoding", b"zstd")], content=content
        )
    except httpx.DecodingError:
        return
    except Exception as exc:  # any raise beats a silent pass
        raise AssertionError(f"{label}: raised {exc!r}, not DecodingError") from exc
    raise AssertionError(
        f"{label}: tail-truncated zstd stream decoded without raising"
    )


def test_tail_truncated_zstd_missing_end_marker_raises():
    body = b"test 123"
    compressed = zstd.ZstdCompressor().compress(body)
    assert len(compressed) > 8
    # Drop the very last byte: the frame can never finalize.
    _assert_decoding_error(compressed[:-1], "missing last byte")


def test_half_truncated_zstd_frame_raises():
    # A genuinely incompressible payload gives a large frame; cutting it in
    # half makes decompress() buffer silently (emitting nothing, raising
    # nothing), so only the flush() step can detect the incomplete frame.
    import os

    payload = os.urandom(65536)
    compressed = zstd.ZstdCompressor().compress(payload)
    assert len(compressed) > 8192
    _assert_decoding_error(compressed[: len(compressed) // 2], "half frame")


def test_complete_frame_still_decodes_after_truncation_checks():
    # Sanity inside the same code path: the fixes that raise on truncated
    # tails must keep decoding complete frames.
    body = b"test 123"
    compressed = zstd.ZstdCompressor().compress(body)
    response = httpx.Response(
        200, headers=[(b"Content-Encoding", b"zstd")], content=compressed
    )
    assert response.content == body