#!/usr/bin/env python3
"""
Origin HTTP server for the drift-dial bench.

Serves a small observatory-data origin with a stations dashboard page,
plus a cookie+nonce authenticated login / logout / session flow.

Usage:
    python3 origin.py <scenario-config.json> <port>

The scenario config declares the page title, the station rows, the login
credentials, the nonce, the session cookie values, and a set of "quirks"
that alter how the HTML page is emitted and how strict the login handshake
is.  The client program (/app/solve.py) is written against the documented
protocol and must work for ANY scenario config.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


class Handler(BaseHTTPRequestHandler):
    cfg = None
    sessions = {}  # session_sid -> {"nonce": str, "authed": bool}

    def log_message(self, *args):
        pass

    # ------------------------------------------------------------------
    # helpers
    # ------------------------------------------------------------------
    def _client_sid(self):
        cookie = self.headers.get("Cookie", "")
        for part in cookie.split(";"):
            part = part.strip()
            if part.startswith("sid="):
                return part[4:]
        return None

    def _reply(self, code, content, ctype="application/json", extra=None):
        if isinstance(content, (dict, list)):
            content = json.dumps(content)
        if not isinstance(content, bytes):
            content = content.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(content)))
        for k, v in (extra or []):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(content)

    # ------------------------------------------------------------------
    # page rendering
    # ------------------------------------------------------------------
    def _stations_dashboard(self):
        cfg = self.cfg
        qu = cfg.get("quirks", {})
        gap = "\n\n  " if qu.get("whitespace") else ""

        parts = []
        parts.append("<!DOCTYPE html>\n<html lang=\"en\">\n<head>")
        parts.append("<title>{t}</title>".format(t=cfg["title"]))
        parts.append("</head>\n<body>")
        parts.append("<header><h1>{t}</h1></header>".format(t=cfg["title"]))
        parts.append('<table id="stations">')
        if not qu.get("no_header"):
            parts.append(
                '<tr class="head"><th>ID</th><th>STATION</th>'
                '<th>CITY</th><th>TEMP_F</th></tr>'
            )

        for st in cfg["stations"]:
            cells = [str(st["id"]), str(st["name"]), str(st["city"]), str(st["temp"])]
            if st["id"] in qu.get("missing_cells", []):
                cells = cells[:3]  # row is short: no TEMP_F cell emitted
            if st["id"] in qu.get("empty_city", []):
                cells[2] = ""

            row = "<tr>"
            for idx in range(4):
                if idx < len(cells):
                    row += gap + "<td>" + cells[idx] + "</td>" + gap
            row += "</tr>"
            parts.append(row)

        if qu.get("footer"):
            parts.append(
                '<tr class="footer"><td class="footer">{n} stations total</td></tr>'
                .format(n=len(cfg["stations"])))
        parts.append("</table>")

        if qu.get("decoy"):
            parts.append('<table id="algorithms">')
            parts.append("<tr><td>A--100</td><td>0.81</td></tr>")
            parts.append("<tr><td>A--101</td><td>0.77</td></tr>")
            parts.append("</table>")

        parts.append("</body>\n</html>")
        body = "".join(parts)
        # optional messy newline padding between rows
        if qu.get("whitespace"):
            body = body.replace("<tr>", "\n\n<tr>").replace("</tr>", "</tr>\n\n")
        return body

    def _login_page(self):
        cfg = self.cfg
        return (
            '<!DOCTYPE html><html><head><title>sign in</title></head><body>'
            '<form id="login" method="post" action="/login">'
            '<input type="hidden" name="nonce" value="{n}"/>'.format(n=cfg["nonce"]) +
            '<label>username<input name="username" value="{u}"/></label>'.format(
                u=cfg["login_user"]) +
            '<label>password<input type="password" name="password"/></label>'
            '<button type="submit">log in</button>'
            '</form></body></html>'
        )

    # ------------------------------------------------------------------
    # routing
    # ------------------------------------------------------------------
    def _path(self):
        return self.path.split("?", 1)[0].rstrip("/") or "/"

    def do_GET(self):
        path = self._path()
        if path == "/":
            self._reply(200, self._stations_dashboard(), "text/html; charset=utf-8")
            return
        if path == "/login":
            pre = self.cfg["session"]["before"]
            self.sessions[pre] = {"nonce": self.cfg["nonce"], "authed": False}
            self._reply(
                200, self._login_page(), "text/html; charset=utf-8",
                extra=[("Set-Cookie", "sid=%s; Path=/" % pre)])
            return
        if path == "/session":
            sid = self._client_sid()
            sess = self.sessions.get(sid)
            if sess and sess["authed"]:
                self._reply(200, {"sid": sid, "logged_in": True})
            else:
                self._reply(401, {"ok": False, "error": "not authenticated"})
            return
        self._reply(404, {"ok": False})

    def do_POST(self):
        path = self._path()
        cfg = self.cfg
        if path == "/login":
            sid = self._client_sid()
            sess = self.sessions.get(sid)
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length).decode("utf-8", "ignore") if length else ""
            form = parse_qs(raw)
            cred_ok = (
                form.get("username", [""])[0] == cfg["login_user"]
                and form.get("password", [""])[0] == cfg["login_pass"]
            )
            nonce_ok = (
                form.get("nonce", [""])[0] == cfg["nonce"]
                and sess is not None
                and sess.get("nonce") == cfg["nonce"]
            )
            if cfg.get("quirks", {}).get("header_nonce"):
                nonce_ok = nonce_ok and self.headers.get("X-Nonce", "") == cfg["nonce"]
            if cred_ok and nonce_ok:
                post = cfg["session"]["after"]
                self.sessions[post] = {"nonce": cfg["nonce"], "authed": True}
                self._reply(
                    200, {"ok": True, "sid": post},
                    extra=[("Set-Cookie", "sid=%s; Path=/" % post)])
            else:
                self._reply(401, {"ok": False})
            return

        if path == "/logout":
            sid = self._client_sid()
            sess = self.sessions.get(sid)
            if sess and sess["authed"]:
                sess["authed"] = False
                self._reply(200, {"ok": True, "logged_out": True})
            else:
                self._reply(401, {"ok": False})
            return

        self._reply(404, {"ok": False})


def main():
    config_path, port = sys.argv[1], int(sys.argv[2])
    Handler.cfg = load_json(config_path)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()