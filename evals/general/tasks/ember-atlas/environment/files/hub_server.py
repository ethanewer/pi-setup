#!/usr/bin/env python3
"""Ridgetop model hub — a minimal, Hugging Face Hub-style model server used by
the ember-atlas benchmark (loopback only, no auth).

Implements just enough of the hub REST surface for huggingface_hub clients:

  GET /health
  GET /api/models/<repo_id>                       (revision defaults to main)
  GET /api/models/<repo_id>/revision/<revision>
  HEAD /<repo_id>/resolve/<revision>/<filename>   (ETag = file sha256)
  GET  /<repo_id>/resolve/<revision>/<filename>

Repos live on disk under --root: <root>/<repo_id with '/'->'/' path>/<files>.
"""
import argparse
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    root = "/app/hub"

    def log_message(self, *a):
        pass

    # ---------------- helpers ----------------
    def _repo_dir(self, repo_id):
        rid = repo_id.strip("/")
        if not rid or ".." in rid.split("/"):
            return None
        full = os.path.realpath(os.path.join(self.root, rid))
        root_abs = os.path.realpath(self.root)
        if not full.startswith(root_abs + os.sep):
            return None
        if not os.path.isdir(full):
            return None
        return full

    def _model_info(self, repo_id, revision):
        if revision not in ("main",):
            return None
        d = self._repo_dir(repo_id)
        if d is None:
            return None
        names = []
        for dirpath, _dirs, files in os.walk(d):
            for fn in sorted(files):
                rel = os.path.relpath(os.path.join(dirpath, fn), d)
                names.append(rel)
        if not names:
            return None
        names.sort()
        digest = hashlib.sha256()
        for rel in names:
            digest.update(rel.encode())
            digest.update(hashlib.sha256(
                open(os.path.join(d, rel), "rb").read()).digest())
        sha = digest.hexdigest()
        return {"id": repo_id, "sha": sha, "revision": revision,
                "siblings": [{"rfilename": n} for n in names]}

    def _repo_sha(self, d):
        digest = hashlib.sha256()
        names = []
        for dirpath, _dirs, files in os.walk(d):
            for fn in sorted(files):
                names.append(os.path.relpath(os.path.join(dirpath, fn), d))
        names.sort()
        for rel in names:
            digest.update(rel.encode())
            digest.update(hashlib.sha256(
                open(os.path.join(d, rel), "rb").read()).digest())
        return digest.hexdigest()

    def _file_path(self, repo_id, revision, filename):
        # revision is an opaque token (e.g. "main" or a commit sha) — the
        # working tree is the single served revision.
        del revision
        d = self._repo_dir(repo_id)
        if d is None:
            return None
        rel = os.path.normpath(filename)
        if rel.startswith("..") or rel.startswith("/"):
            return None
        fp = os.path.realpath(os.path.join(d, rel))
        if not fp.startswith(d + os.sep) or not os.path.isfile(fp):
            return None
        return fp

    def _send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command == "GET":
            self.wfile.write(body)

    # ---------------- routes ----------------
    def _serve_file(self, fp, repo_id, body=False):
        sha = hashlib.sha256(open(fp, "rb").read()).hexdigest()
        d = self._repo_dir(repo_id)
        repo_sha = self._repo_sha(d) if d else ""
        size = os.path.getsize(fp)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("ETag", '"%s"' % sha)
        self.send_header("X-Linked-Etag", '"%s"' % sha)
        self.send_header("X-Repo-Commit", repo_sha)
        self.send_header("X-Repo-Id", repo_id)
        self.send_header("Content-Length", str(size))
        self.end_headers()
        if body:
            with open(fp, "rb") as fh:
                while True:
                    chunk = fh.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)

    def do_GET(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        if parsed.path == "/health":
            return self._send_json({"ok": True})
        # /api/models/<repo...>[/revision/<rev>]
        if len(parts) >= 3 and parts[0] == "api" and parts[1] == "models":
            rest = parts[2:]
            revision = "main"
            if len(rest) >= 3 and rest[-2] == "revision":
                revision = rest[-1]
                rest = rest[:-2]
            repo_id = "/".join(rest)
            info = self._model_info(repo_id, revision)
            if info is None:
                return self._send_json({"error": "not found"}, 404)
            return self._send_json(info)
        # /<repo>/resolve/<rev>/<filename...>
        if len(parts) >= 4 and "resolve" in parts:
            i = parts.index("resolve")
            repo_id = "/".join(parts[:i])
            revision = parts[i + 1]
            filename = "/".join(parts[i + 2:])
            fp = self._file_path(repo_id, revision, filename)
            if fp is None:
                body = b"not found"
                self.send_response(404)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self._serve_file(fp, repo_id, body=True)
            return
        self._send_json({"error": "not found"}, 404)

    def do_HEAD(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        if parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "4")
            self.end_headers()
            return
        if len(parts) >= 4 and "resolve" in parts:
            i = parts.index("resolve")
            repo_id = "/".join(parts[:i])
            revision = parts[i + 1]
            filename = "/".join(parts[i + 2:])
            fp = self._file_path(repo_id, revision, filename)
            if fp is not None:
                self._serve_file(fp, repo_id, body=False)
                return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--bind", default="127.0.0.1")
    args = ap.parse_args()
    Handler.root = args.root
    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
