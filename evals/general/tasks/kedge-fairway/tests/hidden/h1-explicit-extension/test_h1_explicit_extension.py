# Hidden case h1 for kedge-fairway: a zero-byte body served with an explicit
# Content-Type and a pre-set filename extension.  The upstream regression test
# (extracted into /opt/golden) requests a URL with no extension and no content
# type, so this drives the same zero-length branch from different inputs.
#
# A repaired checkout must refuse the empty download with a WARNING and leave
# no file behind; a non-empty control download through the same downloader
# must keep working.  Each test uses its own fresh output directory so
# repeated runs in one container can never collide on artifact paths.
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
        if self.path == "/logo.png":
            body, ctype = b"", "image/png"
        elif self.path == "/ok.txt":
            body, ctype = b"hello", "text/plain"
        else:
            self.send_response(404)
            self.wfile.write(b"not-found")
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

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


def new_project(basedir):
    config.set((), "base-directory", basedir)
    job = Job()
    return downloader.find("http")(job), job


def prep(job, name, extension):
    kwdict = {
        "category": "test",
        "subcategory": "test",
        "filename": name,
        "extension": extension,
    }
    pf = job.pathfmt
    pf.set_directory(kwdict)
    pf.set_filename(kwdict)
    pf.build_path()
    return pf


def capture_download(dl, job, url, name, extension):
    logs = []

    class C(logging.Handler):
        def emit(self, record):
            logs.append(record.getMessage())

    logging.getLogger("downloader.http").addHandler(C())
    pf = prep(job, name, extension)
    success = dl.download(url, pf)
    return success, pf, logs


def test_zero_length_with_extension_and_content_type():
    basedir = tempfile.mkdtemp(prefix="kedge-fairway-h1-", dir="/tmp")
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    host, port = server.server_address
    threading.Thread(target=server.serve_forever, daemon=True).start()
    dl, job = new_project(basedir)

    success, pf, logs = capture_download(
        dl, job, "http://{}:{}/logo.png".format(host, port), "logo", "png")

    assert success is False, "empty download must be refused"
    assert any("Empty file" in message for message in logs), (
        "expected an 'Empty file' WARNING on the downloader logger")
    assert not (pf.temppath and os.path.exists(pf.temppath)), (
        "no file may be left behind for a refused empty download")


def test_control_download_still_works():
    basedir = tempfile.mkdtemp(prefix="kedge-fairway-h1c-", dir="/tmp")
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    host, port = server.server_address
    threading.Thread(target=server.serve_forever, daemon=True).start()
    dl, job = new_project(basedir)

    success, pf, logs = capture_download(
        dl, job, "http://{}:{}/ok.txt".format(host, port), "ok", "txt")

    assert success is True, "a non-empty download must still succeed"
    assert not any("Empty file" in message for message in logs)
    with pf.open("rb") as fp:
        assert fp.read() == b"hello"