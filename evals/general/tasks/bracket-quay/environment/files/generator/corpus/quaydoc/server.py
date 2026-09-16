"""The built-in development server (stdlib ``http.server``)."""

from __future__ import annotations

import functools
import http.server
import os
import socketserver


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Serves a directory without the default per-request stderr log."""

    def log_message(self, format, *args):  # noqa: A002
        pass

    def end_headers(self):
        # static content is immutable between rebuilds; let clients cache
        self.send_header("Cache-Control", "public, max-age=60")
        super().end_headers()

    def do_GET(self):
        if self.path in ("/__quaydoc/", "/__quaydoc"):
            self._serve_build_info()
            return
        super().do_GET()

    def _serve_build_info(self):
        """Expose build.json (or a placeholder) at /__quaydoc/."""
        import json as _json
        info_path = os.path.join(self.directory, "build.json")
        if os.path.isfile(info_path):
            try:
                with open(info_path, encoding="utf-8") as fh:
                    body = fh.read()
            except OSError:
                body = "{}"
        else:
            body = _json.dumps({"note": "no build.json in this directory"})
        payload = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def send_error(self, code, message=None, explain=None):
        if code == 404:
            try:
                with open(os.path.join(self.directory, "404.html"),
                          "rb") as fh:
                    body = fh.read()
                self.send_response(404)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            except OSError:
                pass
        super().send_error(code, message, explain)


def serve(build_dir, host="127.0.0.1", port=8000):
    """Serve ``build_dir`` on ``host:port`` until interrupted."""
    build_dir = os.path.abspath(build_dir)
    if not os.path.isdir(build_dir):
        raise FileNotFoundError(f"{build_dir}: not a directory")
    handler = functools.partial(_QuietHandler, directory=build_dir)
    with socketserver.ThreadingTCPServer((host, port), handler) as httpd:
        httpd.daemon_threads = True
        print(f"Serving {build_dir} at http://{host}:{port}/ "
              "(Ctrl+C to stop)")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")
