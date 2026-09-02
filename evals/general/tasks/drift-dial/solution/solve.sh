#!/usr/bin/env bash
# Oracle / reference solution for drift-dial.
# Writes the real client program, runs it against a live origin to produce the
# answer artifact, then repairs the npm tree and installs it completely.
set -euo pipefail
cd /app

# -------------------------------------------------------------
# 1) Author the delivered client program.
# -------------------------------------------------------------
cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""drift-dial HTTP client (deliverable).

Fetches and parses the stations dashboard from a live origin, then drives a
full cookie+nonce login / session / logout handshake, and writes a documented
JSON report to --out.

Usage:
    python3 solve.py --origin http://127.0.0.1:PORT --out /path/out.json
"""
import argparse
import json
import urllib.request
import urllib.parse
from http.cookiejar import CookieJar
from html.parser import HTMLParser

LOGIN_USER = "tinker"
LOGIN_PASS = "ironclad-2024"


class DashboardParser(HTMLParser):
    """Extracts <title> and the station rows of the <table id="stations">.

    Rules applied (per the task contract):
      * only the table whose id == "stations" is used (decoy tables ignored)
      * a data row must contain at least one <td> (header/th-only rows skipped)
      * a data row must have at least two cells (footer/summary rows skipped)
      * missing trailing cells default to "" (tempF becomes null when missing)
    """

    def __init__(self):
        super().__init__()
        self.title = ""
        self._in_title = False
        self._in_table = False
        self._table_kind = None
        self._row = None          # {"cells":[str], "has_td":bool}
        self._cell = None
        self._buf = []
        self.stations = []        # list of {"id","name","city","tempF"}

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "title":
            self._in_title = True
        elif tag == "table":
            self._in_table = True
            self._table_kind = a.get("id", "")
        elif tag == "tr":
            if self._in_table:
                self._row = {"cells": [], "has_td": False}
        elif tag in ("td", "th"):
            if self._row is not None:
                if tag == "td":
                    self._row["has_td"] = True
                self._cell = tag
                self._buf = []

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        elif self._cell is not None:
            self._buf.append(data)

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        elif tag in ("td", "th"):
            if self._cell is not None and self._row is not None:
                self._row["cells"].append("".join(self._buf).strip())
                self._cell = None
        elif tag == "tr":
            if self._row is not None and self._table_kind == "stations":
                cells = self._row["cells"]
                if self._row["has_td"] and len(cells) >= 2:
                    self._emit(cells)
            self._row = None
        elif tag == "table":
            self._in_table = False
            self._table_kind = None

    def _emit(self, cells):
        temp_raw = cells[3] if len(cells) > 3 else ""
        temp = None
        try:
            temp = float(temp_raw)
        except (ValueError, TypeError):
            temp = None if not str(temp_raw).strip() else None
            # keep null for genuinely missing temp; a junk numeric stays null
        self.stations.append({
            "id": cells[0],
            "name": cells[1],
            "city": cells[2] if len(cells) > 2 else "",
            "tempF": temp,
        })


class LoginParser(HTMLParser):
    """Reads the hidden form nonce off the /login page."""

    def __init__(self):
        super().__init__()
        self.nonce = None

    def handle_starttag(self, tag, attrs):
        if tag == "input":
            a = dict(attrs)
            if a.get("name") == "nonce":
                self.nonce = a.get("value")


class SessionClient:
    def __init__(self, origin):
        self.origin = origin.rstrip("/")
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(CookieJar()))

    def _get(self, path):
        with self.opener.open(self.origin + path, timeout=15) as r:
            return r.read().decode("utf-8", "ignore")

    def _post(self, path, data=None, headers=None):
        body = (data or "").encode() if isinstance(data, str) else (data or b"")
        req = urllib.request.Request(self.origin + path, data=body, method="POST")
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        with self.opener.open(req, timeout=15) as r:
            return r.read().decode("utf-8", "ignore")

    def dashboard(self):
        p = DashboardParser()
        p.feed(self._get("/"))
        return p

    def login_session_logout(self):
        lp = LoginParser()
        lp.feed(self._get("/login"))
        nonce = lp.nonce
        if nonce is None:
            raise RuntimeError("no nonce found on login page")
        form = urllib.parse.urlencode({
            "username": LOGIN_USER, "password": LOGIN_PASS, "nonce": nonce
        })
        # X-Nonce header is sent always; ratified only when the server asks for it.
        self._post("/login", form, headers={"X-Nonce": nonce})
        sess = json.loads(self._get("/session"))
        sid = sess.get("sid")
        lo = json.loads(self._post("/logout", b""))
        return {
            "sid": sid,
            "logged_in": bool(sess.get("logged_in")),
            "logged_out": bool(lo.get("logged_out")),
        }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--origin", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    client = SessionClient(args.origin)
    dashboard = client.dashboard()
    session = client.login_session_logout()

    result = {
        "title": dashboard.title.strip(),
        "stations": dashboard.stations,
        "session": session,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
PY
chmod +x /app/solve.py

# -------------------------------------------------------------
# 2) Run the client against the live reference origin to make answer.json
# -------------------------------------------------------------
python3 /app/origin.py /app/ref_config.json 20080 &
ORIGIN_PID=$!
trap 'kill $ORIGIN_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do
  if python3 -c 'import urllib.request,sys
try:
    urllib.request.urlopen("http://127.0.0.1:20080/", timeout=0.5)
    sys.exit(0)
except Exception:
    sys.exit(1)'; then
    break
  fi
  sleep 0.2
done

python3 /app/solve.py --origin "http://127.0.0.1:20080" --out /app/answer.json
kill $ORIGIN_PID 2>/dev/null || true
trap - EXIT

# -------------------------------------------------------------
# 3) npm: repair the broken transitive pin and install the full tree
# -------------------------------------------------------------
python3 - <<'PY'
import json
p = "vendor/sector-srv/package.json"
d = json.load(open(p, encoding="utf-8"))
d["dependencies"]["motif"] = "file:../motif"
json.dump(d, open(p, "w", encoding="utf-8"), indent=2)
print("repaired sector-srv manifest:", d["dependencies"])
PY
npm install --no-audit --no-fund
node -e 'const s=require("sector-srv"); const st=s.stamp(); if(st.stream!=="motif-core"||st.build!==1) process.exit(1); console.log("tree ok")'

echo "solve.sh finished"