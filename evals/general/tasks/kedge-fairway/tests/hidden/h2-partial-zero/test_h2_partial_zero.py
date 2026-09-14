# Hidden case h2 for kedge-fairway: the zero-length response arrives through
# the 206 Partial Content branch, with a Content-Range total of 0.  The
# upstream regression test (extracted into /opt/golden) reaches the
# zero-length handling via a plain 200 response, so this exercises the same
# branch from a different HTTP status path.
#
# A repaired checkout must refuse the download with a WARNING and leave no
# file behind.  Each test uses its own fresh output directory so repeated
# runs in one container can never collide on artifact paths.
import http.server
import logging
import os
import sys
import tempfile
import threading

sys.path.insert(0, "/app/src")

from gallery_dl import config, downloader, extractor, output, path  # noqa: E402


class Handler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        # zero-total partial content response for any request on /data
        self.send_response(206)
        self.send_header("Content-Length", "0")
        self.send_header("Content-Range", "bytes 0--1/0")
        self.end_headers()

    def log_message(self, *args):
        pass


class Job:

    def __init__(self):
        self.extractor = extractor.find("generic:https://example.org/")
        self.extractor.initialize()
        self.pathfmt = path.PathFormat(self.extractor)
        self.out = output.NullOutput()
        self.get_logger = logging.getLogger

    def register_hooks(self, hooks, options=None):
        pass


def test_partial_content_zero_total():
    basedir = tempfile.mkdtemp(prefix="kedge-fairway-h2-", dir="/tmp")
    config.set((), "base-directory", basedir)

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    host, port = server.server_address
    threading.Thread(target=server.serve_forever, daemon=True).start()

    job = Job()
    dl = downloader.find("http")(job)

    logs = []

    class C(logging.Handler):
        def emit(self, record):
            logs.append(record.getMessage())

    logging.getLogger("downloader.http").addHandler(C())

    kwdict = {
        "category": "test",
        "subcategory": "test",
        "filename": "data",
        "extension": "bin",
    }
    pf = job.pathfmt
    pf.set_directory(kwdict)
    pf.set_filename(kwdict)
    pf.build_path()

    success = dl.download("http://{}:{}/data".format(host, port), pf)

    assert success is False, "empty partial-content download must be refused"
    assert any("Empty file" in message for message in logs), (
        "expected an 'Empty file' WARNING on the downloader logger")
    assert not (pf.temppath and os.path.exists(pf.temppath)), (
        "no file may be left behind for a refused empty download")