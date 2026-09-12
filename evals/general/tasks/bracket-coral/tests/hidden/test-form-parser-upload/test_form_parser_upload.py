"""Hidden case 2: end-to-end upload through werkzeug's own form parser
(MultiPartParser), with a small buffer_size so the body reaches the multipart
decoder in many small chunks, exactly like a socket-fed upload.  The stored
file must be byte-for-byte the uploaded content."""
import io

import pytest

from werkzeug.formparser import MultiPartParser


def upload_content(content, boundary, buffer_size):
    body = (
        b"--" + boundary + b"\r\n"
        b'Content-Disposition: form-data; name="file"; filename="upload.bin"\r\n'
        b"Content-Type: application/octet-stream\r\n\r\n"
        + content
        + b"\r\n--" + boundary + b"--\r\n"
    )
    parser = MultiPartParser(
        stream_factory=lambda **kw: io.BytesIO(), buffer_size=buffer_size
    )
    form, files = parser.parse(io.BytesIO(body), boundary, len(body))
    return files["file"].read()


BOUNDARY = b"endtoend-77"

CASES = [
    b"bin\x00\xc3\xa9\n",
    b"trailing\n",
    b"second line after cr\r\n",
    b"plain-control",
]


@pytest.mark.parametrize("content", CASES)
def test_upload_round_trips_through_form_parser(content):
    for buffer_size in (5, 7, 11, 31):
        received = upload_content(content, BOUNDARY, buffer_size)
        assert received == content, (buffer_size, content, received)