#!/usr/bin/env python3
"""Reference reproduction for the reserved WebSocket close status 1006 bug.

Drives aiohttp's pure-Python WebSocket frame reader with a raw Close frame
carrying status 1006 and reports whether the reader treats it as a protocol
violation.  Exit status 0 plus a final "RESULT: PASS" line exactly when the
reader raises a protocol error for status 1006; while the bug is present the
reader accepts the frame as a normal close and this script exits non-zero.
"""

import asyncio
import struct
import sys
from unittest import mock

from aiohttp._websocket.reader import WebSocketDataQueue
from aiohttp.http import WebSocketError, WebSocketReader, WSCloseCode


def close_frame_with_code(code: int) -> bytes:
    # RFC 6455: FIN | CLOSE (0x88), payload length, 2-byte big-endian code.
    payload = struct.pack("!H", code)
    return bytes([0x88, len(payload)]) + payload


def main() -> int:
    loop = asyncio.new_event_loop()
    try:
        out = WebSocketDataQueue(
            mock.Mock(_reading_paused=False), 2 ** 16, loop=loop
        )
        reader = WebSocketReader(
            out, 4 * 1024 * 1024, compress=True, decode_text=True
        )
        try:
            reader._feed_data(close_frame_with_code(1006))
        except WebSocketError as exc:
            if exc.code == WSCloseCode.PROTOCOL_ERROR:
                print("RESULT: PASS")
                return 0
            print(
                "RESULT: FAIL (raised WebSocketError code"
                f" {exc.code}; expected PROTOCOL_ERROR 1002)",
                file=sys.stderr,
            )
            return 1
        print(
            "RESULT: FAIL (close frame with reserved status 1006 was accepted"
            " as a normal close)",
            file=sys.stderr,
        )
        return 1
    finally:
        loop.close()


if __name__ == "__main__":
    sys.exit(main())