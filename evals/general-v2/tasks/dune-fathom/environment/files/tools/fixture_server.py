#!/usr/bin/env python3
"""Local fixture server for the dune-fathom task.

Serves two fixed files byte-for-byte so the agent can practise a real HTTP
fetch-and-persist (competency: retrieve remote file contents byte-for-byte and
persist them at required paths):

    GET /alpha  -> application/octet-stream raw binary payload
    GET /beta   -> text/plain document with a BOM-free UTF-8 payload

The verifier launches its own copy of this server and compares the bytes it
serves against the files the agent wrote to /app/delivered/.  The payloads are
hard constants below so verification is deterministic.
"""
import http.server
import os
import socketserver
import sys

HOST = "0.0.0.0"
PORT = int(os.environ.get("FIXTURE_PORT", "9898"))


class Server(socketserver.TCPServer):
    allow_reuse_address = True

# Deterministic binary payload: a control-byte preamble, an embedded NUL, a
# high-bit byte (0xff), a newline inside the middle, then a tail. These bytes
# are NOT valid UTF-8, so any text-transcoding step (encoding="...") would
# corrupt them and the verifier would see a mismatch.
ALPHA = (
    b"DUNE\x00FATHOM"
    b"\xff\xfe\x01\x80"
    b"\x0aline-one\x00.\n"
    b"\x7f^~tail\n"
)

# Text payload: includes escaped high-bit chars and a trailing newline, so any
# accidental re-encoding (e.g. reading as latin-1 then writing utf-8, or
# stripping trailing whitespace) would change the bytes.
BETA = (
    b"fathom-beta-document\n"
    b"kjern\xc3\xa6re core\x3b avec c\x3a\xc3\xa7a and \xc3\xa9\xc3\xa8.\n"
    b"trailing newline follows\n"
)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/alpha", "/alpha/", "/alpha?x=1"):
            body, ctype = ALPHA, "application/octet-stream"
        elif self.path in ("/beta", "/beta/", "/beta?x=1"):
            body, ctype = BETA, "text/plain; charset=utf-8"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    with Server((HOST, PORT), Handler) as httpd:
        httpd.serve_forever()