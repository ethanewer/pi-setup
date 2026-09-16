#!/usr/bin/env python3
"""Probe for the multipart-upload corruption in this werkzeug checkout.

Drives werkzeug's low-level multipart decoder (the same component the form
parser hands uploaded file bodies to) the way a real server receives an upload:
first a chunk carrying the part headers and the file bytes, then a later chunk
carrying the closing boundary.  When the parser is correct, the decoded file
bytes are byte-for-byte identical to the bytes that were uploaded; on this
checkout the newline bytes that belong around the part boundary get mixed into
the file content.

Exit status is 0 when every upload round-trips exactly, non-zero otherwise.
"""
import sys

from werkzeug.sansio.multipart import Data, Epilogue, MultipartDecoder, NeedData


def receive_upload(boundary, body, content):
    """Feed `body` in two chunks -- everything up to the end of the file bytes,
    then the rest -- draining events between arrivals, and return all bytes the
    decoder reports for the file Data events."""
    decoder = MultipartDecoder(boundary)
    split = body.index(b"\r\n\r\n") + 2 + len(content)
    received = b""
    decoder.receive_data(body[:split])
    while True:
        event = decoder.next_event()
        if isinstance(event, NeedData):
            break
        if isinstance(event, Data):
            received += event.data
        if isinstance(event, Epilogue):
            return received
    decoder.receive_data(body[split:])
    decoder.receive_data(None)
    stale = 0
    while stale < 5:
        event = decoder.next_event()
        if isinstance(event, Data):
            received += event.data
        if isinstance(event, Epilogue):
            break
        stale = stale + 1 if isinstance(event, NeedData) else 0
    return received


def multipart_body(boundary, content):
    return (
        b"\r\n--" + boundary + b"\r\n"
        b'Content-Disposition: form-data; name="file"; filename="blob.bin"\r\n'
        b"Content-Type: application/octet-stream\r\n\r\n"
        + content
        + b"\r\n--" + boundary + b"--\r\n"
    )


def main():
    cases = [
        # (label, boundary, uploaded content)
        ("upload ending in bare CR", b"BOUNDARY-abc", b"x\ry"),
        ("upload consisting of blank lines", b"BOUNDARY-abc", b"\n\n"),
        ("upload ending in CRLF, preceded by CR", b"BOUNDARY-abc", b"\r\nX\r\n"),
        ("upload with final blank line and trailer", b"BOUNDARY-abc", b"\n\nB"),
        ("upload without trailing newline", b"BOUNDARY-abc", b"sentinel"),
    ]
    failed = 0
    for label, boundary, content in cases:
        body = multipart_body(boundary, content)
        received = receive_upload(boundary, body, content)
        ok = received == content
        print(f"{'ok  ' if ok else 'FAIL'} {label}:")
        print(f"     uploaded {content!r}   received {received!r}")
        if not ok:
            failed += 1
    if failed:
        print(f"\n{failed} upload(s) corrupted: the multipart decoder does not "
              f"return the uploaded bytes exactly.")
        return 1
    print("\nAll uploads round-trip exactly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())