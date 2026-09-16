#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""kedge-fairway reproduction: zero-byte HTTP responses must be refused.

Drives a real download of a zero-byte body (Content-Length: 0) through the
checked-out gallery-dl HttpDownloader using a loopback HTTP server, and
reports whether the checkout handles it correctly.

Exit status (the verifier contract):
  0  the checkout refused the empty download: a WARNING was emitted, the
     download did not report success, and no file was written
  non-zero  the checkout silently succeeded (an empty file was written and the
     download reported success)

Self-contained: no network access, loopback only, terminates on its own.
Also rejects a checkout that forgot the empty-body case entirely (downloaded
file exists) and a runtime where the empty body is refused without a warning.
"""
import http.server
import logging
import os
import sys
import tempfile
import threading

sys.path.insert(0, "/app/src")

from gallery_dl import config, downloader, extractor, output, path  # noqa: E402


class EmptyHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


class _Job:

    def __init__(self):
        self.extractor = extractor.find("generic:https://example.org/")
        self.extractor.initialize()
        self.pathfmt = path.PathFormat(self.extractor)
        self.out = output.NullOutput()
        self.get_logger = logging.getLogger

    def register_hooks(self, hooks, options=None):
        pass


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), EmptyHandler)
    host, port = server.server_address
    threading.Thread(target=server.serve_forever, daemon=True).start()

    basedir = tempfile.mkdtemp(prefix="kedge-fairway-", dir="/tmp")
    config.set((), "base-directory", basedir)

    job = _Job()
    downloader_instance = downloader.find("http")(job)

    warnings = []

    class _Capture(logging.Handler):
        def emit(self, record):
            warnings.append(record.getMessage())

    logging.getLogger("downloader.http").addHandler(_Capture())

    kwdict = {
        "category": "test",
        "subcategory": "test",
        "filename": "empty",
        "extension": "bin",
    }
    pf = job.pathfmt
    pf.set_directory(kwdict)
    pf.set_filename(kwdict)
    pf.build_path()

    url = "http://{}:{}/empty".format(host, port)
    print("downloading", url)
    success = downloader_instance.download(url, pf)

    left_behind = bool(pf.temppath) and os.path.exists(pf.temppath)
    warned = any("Empty file" in message for message in warnings)

    print("reported success:", success)
    print("warning emitted: ", warned, warnings)
    print("file written:    ", left_behind)
    print("output dir:      ", basedir)

    if success is False and warned and not left_behind:
        print("RESULT: empty download correctly refused")
        return 0
    print("RESULT: BUG PRESENT - zero-byte download not refused correctly")
    return 1


if __name__ == "__main__":
    sys.exit(main())