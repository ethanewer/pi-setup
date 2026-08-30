#!/usr/bin/env python3
"""Verifier for dune-fathom (executes-deliverable).

Boots the grader-owned copy of /app/server.py, then exercises every deliverable:

  * server reachable on both 127.0.0.1 and the container IP (0.0.0.0 bind),
  * /app/server.out records a clean boot with the readiness line,
  * DB table == source CSV == /app/dump.csv (three-way consistency),
  * /app/delivered/alpha.bin & beta.txt byte-equal to a freshly booted copy of
    the fixture server,
  * hidden route scenarios (fibonacci, block/tx status, paginated accounts,
    plain-text echo) all conform to the contract.

Exits 0 iff every check passes (tests/test.sh writes the reward). Only the
Python standard library is used.
"""
import csv
import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOST = "127.0.0.1"
PORT = 8787
BASE = f"http://{HOST}:{PORT}"
LEAD = b"FATHOM-API-UP 0.0.0.0:8787"

DB = "/app/data/dump_chain.db"
SRC = "/app/data/accounts.csv"
DUMP = "/app/dump.csv"
SERVER = "/app/server.py"
SERVEROUT = "/app/server.out"
DELIVERED = "/app/delivered"
HIDDEN = "/tests/hidden"

CHECKS = []  # (name, ok, detail)


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + ((" | " + detail) if detail else ""))


def container_ip():
    try:
        out = subprocess.check_output(["hostname", "-I"], text=True).split()
    except Exception:
        out = []
    for w in out:
        w = w.strip()
        if w and not w.startswith("127.") and ":" not in w:
            return w
    return HOST


IPBASE = f"http://{container_ip()}:{PORT}"


def http(base, path, params=None):
    url = base + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    try:
        r = urllib.request.urlopen(url, timeout=5)
        return r.getcode(), r.read(), (r.headers.get("Content-Type", "") or "").lower()
    except urllib.error.HTTPError as e:
        return e.code, e.read(), (e.headers.get("Content-Type", "") or "").lower()
    except Exception as e:
        return -1, b"", ""


def as_json(body):
    try:
        return json.loads(body.decode("utf-8"))
    except Exception:
        return None


def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def db_rows():
    con = sqlite3.connect(DB)
    try:
        return con.execute(
            "SELECT id, address, balance FROM accounts ORDER BY id"
        ).fetchall()
    finally:
        con.close()


def normalize_rows(rows):
    out = []
    for r in rows:
        out.append((int(r[0]), str(r[1]).strip(), int(r[2])))
    return out


def read_source():
    with open(SRC, newline="") as fh:
        rows = []
        for row in csv.DictReader(fh):
            rows.append((int(row["id"]), str(row["address"]).strip(), int(row["balance"])))
        return rows


def read_dump():
    with open(DUMP, newline="") as fh:
        rd = csv.reader(fh)
        header = next(rd)
        return header, normalize_rows(rd)


def main():
    # ---------- Deliverables present ----------
    for p in (SERVER, SERVEROUT, DUMP, DB,
              "/app/delivered/alpha.bin", "/app/delivered/beta.txt"):
        check("present " + p, os.path.isfile(p))

    # ---------- Boot the server ourselves (grader-owned instance) ----------
    # The agent may have left one running; make sure only one clean instance is up.
    try:
        subprocess.run(["pkill", "-f", SERVER], capture_output=True)
    except Exception:
        pass
    time.sleep(0.5)
    if os.path.exists(SERVEROUT):
        os.remove(SERVEROUT)
    try:
        proc = subprocess.Popen(
            ["python3", SERVER],
            cwd="/app",
            stdout=open(SERVEROUT, "ab"),
            stderr=subprocess.STDOUT,
        )
    except Exception as e:
        check("server started", False, str(e))
        proc = None

    server_up = False
    if proc is not None:
        for _ in range(80):
            try:
                code, body, _ct = http(BASE, "/health")
                if code == 200 and as_json(body) == {"status": "ok"}:
                    server_up = True
                    break
            except Exception:
                pass
            time.sleep(0.5)
    check("server healthy on 127.0.0.1", server_up)

    # ---------- Reachable via container IP (all-interface bind) ----------
    if server_up:
        code, body, _ct = http(IPBASE, "/health")
        ok = code == 200 and as_json(body) == {"status": "ok"}
        check("server healthy on container IP " + IPBASE, ok, f"code={code}")
    else:
        check("server healthy on container IP " + IPBASE, False, "not up")

    # ---------- Readiness log ----------
    log = b""
    if server_up and os.path.exists(SERVEROUT):
        time.sleep(1.0)
        log = open(SERVEROUT, "rb").read()
    check("server.out records readiness line",
          LEAD in log or b"FATHOM-API-UP" in log,
          f"log_bytes={len(log)}")

    # ---------- DB / source / dump three-way consistency ----------
    if os.path.isfile(DB) and os.path.isfile(SRC) and os.path.isfile(DUMP):
        try:
            dbn = db_rows()
        except Exception as e:
            dbn = None
            check("db table readable", False, str(e))
        try:
            src = read_source()
        except Exception as e:
            src = None
            check("source csv readable", False, str(e))
        try:
            hdr, dump = read_dump()
        except Exception as e:
            dump = None
            hdr = None
            check("dump csv readable", False, str(e))
        if dbn is not None and src is not None and dump is not None and hdr is not None:
            dbn = normalize_rows(dbn)
            a = dbn == src
            b = dump == src
            c = hdr == ["id", "address", "balance"]
            check("db == source csv", a, f"db={dbn} src={src}")
            check("dump.csv == source csv", b, f"dump={dump} src={src}")
            check("dump.csv header normalized", c, f"header={hdr}")
            check("db == dump.csv", dbn == dump)
            check("accounts non-empty (6 rows)", len(dbn) == 6, f"n={len(dbn)}")
    else:
        check("db/source/dump present for consistency", False)

    # ---------- Hidden route scenarios ----------
    if server_up:
        run_hidden()
    else:
        for fn in sorted(os.listdir(HIDDEN)):
            if fn.endswith(".json"):
                check("hidden " + fn, False, "server not up")

    # ---------- Byte-for-byte remote fetch ----------
    byte_ok = check_bytes()

    # ---------- Clean stop ----------
    if proc is not None:
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
        check("server cleanly stopped", True)

    all_ok = all(ok for _, ok, _ in CHECKS)
    print("RETURN", "OK" if all_ok else "FAIL", f"passed={sum(ok for _,ok,_ in CHECKS)}/{len(CHECKS)}")
    sys.exit(0 if all_ok else 1)


def run_hidden():
    for fn in sorted(os.listdir(HIDDEN)):
        if not fn.endswith(".json"):
            continue
        try:
            spec = json.load(open(os.path.join(HIDDEN, fn)))
        except Exception as e:
            check("hidden " + fn, False, "bad json: " + str(e))
            continue
        t = spec.get("type")
        if t == "fib":
            run_fib(fn, spec)
        elif t == "path":
            run_path(fn, spec)
        elif t == "accounts":
            run_accounts(fn, spec)
        elif t == "render":
            run_render(fn, spec)
        else:
            check("hidden " + fn, False, "unknown type " + str(t))


def run_fib(fn, spec):
    route = spec["route"]
    n_ok = 0
    for i, c in enumerate(spec["cases"]):
        code, body, _ct = http(BASE, route, c.get("params"))
        j = as_json(body)
        if c["status"] == 400:
            good = code == 400 and j is not None and isinstance(j.get("error"), str) \
                and len(j.get("error", "")) > 0
        else:
            good = code == 200 and j is not None and j.get("k") == c["k"] \
                and j.get("value") == c["value"]
        n_ok += good
    check(f"hidden {fn}", n_ok == len(spec["cases"]), f"{n_ok}/{len(spec['cases'])} cases")


def run_path(fn, spec):
    n_ok = 0
    for c in spec["cases"]:
        code, body, _ct = http(BASE, c["path"])
        j = as_json(body)
        if c["status"] == 200:
            good = code == 200 and j is not None and all(
                j.get(k) == v for k, v in c.get("body", {}).items()
            )
        elif c["status"] == 404:
            need_json = c.get("json_error", False)
            good = code == 404 and (not need_json or (j is not None and bool(j.get("error"))))
        elif c["status"] == 400:
            good = code == 400 and j is not None and bool(j.get("error"))
        else:
            good = False
        n_ok += good
    check(f"hidden {fn}", n_ok == len(spec["cases"]), f"{n_ok}/{len(spec['cases'])} cases")


def run_accounts(fn, spec):
    # Expected pages are derived from the live DB (which was itself cross-checked
    # against the source and dump), so the route must be reading the same rows.
    rows = normalize_rows(db_rows()) if os.path.isfile(DB) else []
    n_ok = 0
    for c in spec["cases"]:
        code, body, _ct = http(BASE, spec["route"], c.get("params"))
        j = as_json(body)
        if c.get("status") == 400:
            good = code == 400 and j is not None and bool(j.get("error"))
        else:
            off, lim = c["offset"], c["limit"]
            if lim is None:
                expected = rows[off:]
            else:
                expected = rows[off:off + lim]
            if code != 200 or j is None:
                good = False
            else:
                got = [(x["id"], x["address"], x["balance"]) for x in j.get("result", [])]
                good = (j.get("total") == len(rows)
                        and len(got) == len(expected)
                        and got == expected)
        n_ok += good
    check(f"hidden {fn}", n_ok == len(spec["cases"]), f"{n_ok}/{len(spec['cases'])} cases")


def run_render(fn, spec):
    n_ok = 0
    for c in spec["cases"]:
        code, body, ct = http(BASE, spec["route"], c.get("params"))
        good = (code == 200
                and ct.startswith("text/plain")
                and body.decode("utf-8") == c["text"])
        n_ok += good
    check(f"hidden {fn}", n_ok == len(spec["cases"]), f"{n_ok}/{len(spec['cases'])} cases")


def check_bytes():
    # Boot the verifier's own copy of the fixture server on a private port and
    # compare its raw payloads to the files the agent wrote (byte-for-byte, no
    # transcoding). The payloads are hard constants, so the serving port is
    # irrelevant to correctness; a private port avoids collisions with any copy
    # the agent left running on 9898.
    FIXPORT = 9899
    env = dict(os.environ, FIXTURE_PORT=str(FIXPORT))
    try:
        fx = subprocess.Popen(
            ["python3", "/app/tools/fixture_server.py"],
            cwd="/app",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
        )
    except Exception as e:
        check("delivered alpha.bin byte-exact", False, str(e))
        check("delivered beta.txt byte-exact", False, str(e))
        return False
    try:
        ok = False
        for _ in range(60):
            try:
                c, _, _ = http(f"http://127.0.0.1:{FIXPORT}", "/alpha")
                if c == 200:
                    ok = True
                    break
            except Exception:
                pass
            time.sleep(0.5)
        if not ok:
            check("delivered byte-exact", False, "fixture server did not come up")
            return False
        for name, fname, path in (
                ("alpha", "alpha.bin", "/app/delivered/alpha.bin"),
                ("beta", "beta.txt", "/app/delivered/beta.txt")):
            _c, got, _ct = http(f"http://127.0.0.1:{FIXPORT}", "/" + name)
            if not os.path.exists(path):
                check(f"delivered {fname} byte-exact", False, "file missing")
                continue
            with open(path, "rb") as fh:
                disk = fh.read()
            check(f"delivered {fname} byte-exact", got == disk,
                  f"served={len(got)}B on_disk={len(disk)}B equal={got == disk}")
        return True
    finally:
        try:
            fx.terminate()
            fx.wait(timeout=5)
        except Exception:
            fx.kill()


if __name__ == "__main__":
    main()
