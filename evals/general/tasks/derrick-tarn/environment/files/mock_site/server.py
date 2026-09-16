#!/usr/bin/env python3
"""Tiny offline HTTP server for the fictional picdrome mock site.

Serves a directory tree as a static website on the loopback interface.
Used both by the development fixture (default root /app/mock_site, default
port 8765) and by the verifier for hidden fixtures (root and port passed on
the command line). Standard library only; no runtime dependencies.
"""
import argparse
import functools
import http.server
import mimetypes
import socketserver


class PicdromeHandler(http.server.SimpleHTTPRequestHandler):
    server_version = "picdrome-mock/1.0"

    def guess_type(self, path):
        """Serve text/* content with an explicit UTF-8 charset.

        gallery-dl decodes page bodies using the charset in the response
        Content-Type header; without one, requests would fall back to
        latin-1 and em-dashes in titles would be mojibake.
        """
        ctype, _ = mimetypes.guess_type(path)
        if ctype is None:
            ctype = "application/octet-stream"
        if ctype.startswith("text/"):
            ctype += "; charset=utf-8"
        return ctype

    def log_message(self, fmt, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description="picdrome mock site server")
    ap.add_argument("--root", default="/app/mock_site",
                    help="directory tree to serve (default: /app/mock_site)")
    ap.add_argument("--port", type=int, default=8765,
                    help="loopback port to listen on (default: 8765)")
    ap.add_argument("--host", default="127.0.0.1",
                    help="interface to bind (default: 127.0.0.1)")
    args = ap.parse_args()

    handler = functools.partial(PicdromeHandler, directory=args.root)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer((args.host, args.port), handler) as httpd:
        print("picdrome mock server listening on "
              f"http://{args.host}:{args.port} serving {args.root}",
              flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()