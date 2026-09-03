#!/usr/bin/env python3
"""sedge-hearth flow harness — independent reference + flow battery.

Drives the deliverable /app/token_service.py over loopback and recomputes
every expected HMAC and claim set from the config file alone (this file
contains no fixed expected outputs). Mode 'visible' runs the battery against
the shipped /app/config.json; mode 'hidden' regenerates hidden configs from
a fixed seed (different secrets, lifetimes, clock skew, users, ports),
writes each to /app/config.json, resets /app/state, and re-runs the exact
same battery — so a service that only handles the visible fixture or that
hardcodes responses fails the hidden runs.

Usage:
    python3 flow_harness.py visible
    python3 flow_harness.py hidden
"""
import base64
import hashlib
import hmac
import json
import os
import random
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

SERVICE = "/app/token_service.py"
CONFIG_PATH = "/app/config.json"
STATE_DIR = "/app/state"
BLACKLIST_PATH = os.path.join(STATE_DIR, "blacklist.json")
ERRLOG = "/tmp/onyx_svc_err.log"

HDR = b'{"alg":"HS256","typ":"JWT"}'
JTI_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{8}$")


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")


def b64url_dec(s):
    return base64.b64decode(s + "=" * (-len(s) % 4), altchars=b"-_", validate=True)


def compact(obj):
    return json.dumps(obj, separators=(",", ":"))


def sign(secret, hb, pb):
    return b64url(hmac.new(secret, ("%s.%s" % (hb, pb)).encode("ascii"),
                           hashlib.sha256).digest())


def craft(secret, claims):
    """Contract-compliant token with the given claims (dict)."""
    hb = b64url(HDR)
    pb = b64url(compact(claims).encode("ascii"))
    return "%s.%s.%s" % (hb, pb, sign(secret, hb, pb))


def _code(body):
    if isinstance(body, dict):
        err = body.get("error")
        if isinstance(err, dict):
            return err.get("code")
    return None


class Client:
    def __init__(self, port):
        self.base = "http://127.0.0.1:%d" % port

    def request(self, method, path, body=None, headers=None):
        hdrs = {k: v for k, v in (headers or {}).items()}
        data = None
        if body is not None:
            data = body.encode("utf-8") if isinstance(body, str) \
                else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(self.base + path, data=data,
                                     method=method, headers=hdrs)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            try:
                payload = json.loads(exc.read().decode("utf-8"))
            except Exception:
                payload = None
            return exc.code, payload
        except Exception as exc:
            raise AssertionError("http %s %s failed: %r" % (method, path, exc))


# ---------------------------------------------------------------------------
# service lifecycle
# ---------------------------------------------------------------------------
def _service_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % name, "rb") as fh:
                cmd = fh.read().replace(b"\x00", b" ")
        except OSError:
            continue
        if b"token_service.py" in cmd:
            found.append(int(name))
    return found


def sweep():
    """Kill any leftover token service processes (agent or previous runs)."""
    for pid in _service_pids():
        try:
            os.kill(pid, 9)
        except OSError:
            pass
    time.sleep(0.3)


def wipe_state():
    for path in (BLACKLIST_PATH, BLACKLIST_PATH + ".tmp"):
        try:
            os.remove(path)
        except OSError:
            pass


def wait_ready(port, proc, tries=60):
    for _ in range(tries):
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def start_service(port):
    errf = open(ERRLOG, "wb")
    proc = subprocess.Popen([sys.executable, SERVICE],
                            stdout=subprocess.DEVNULL, stderr=errf)
    errf.close()
    if not wait_ready(port, proc):
        tail = b""
        try:
            with open(ERRLOG, "rb") as fh:
                tail = fh.read()[-400:]
        except OSError:
            pass
        try:
            proc.kill()
        except OSError:
            pass
        raise AssertionError("%s did not become ready on port %d: %s"
                             % (SERVICE, port, tail.decode("utf-8", "replace")))
    return proc


def stop_service(proc):
    if proc is None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=5)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def read_blacklist(F, tag):
    try:
        with open(BLACKLIST_PATH, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        F.append("%s: blacklist.json unreadable: %s" % (tag, exc))
        return {}
    if (not isinstance(data, dict) or data.get("version") != 1
            or not isinstance(data.get("entries"), dict)):
        F.append("%s: blacklist.json wrong shape: %r" % (tag, data))
        return {}
    return data["entries"]


# ---------------------------------------------------------------------------
# the flow battery
# ---------------------------------------------------------------------------
def battery(cfg, label, now):
    F = []
    port = int(cfg["port"])
    secret = str(cfg["secret"]).encode("utf-8")
    issuer = str(cfg["issuer"])
    tol = int(cfg["clock_skew_sec"])
    la = int(cfg["lifetimes"]["access_sec"])
    lr = int(cfg["lifetimes"]["refresh_sec"])
    users = cfg["users"]
    names = sorted(users)
    if len(names) < 2:
        return F + ["%s: config has fewer than 2 users" % label]

    sweep()
    wipe_state()
    proc = start_service(port)
    cli = Client(port)
    HD = {"X-Onyx-Now": str(now)}
    nonce = [None]
    mints = [0]
    revocations = {}  # jti -> reason (everything the battery revoked)

    def req(method, path, body=None, headers=None):
        hdrs = dict(HD)
        if headers:
            hdrs.update(headers)
        return cli.request(method, path, body, hdrs)

    def expect_mint(tag, tok, sub, typ):
        """Recompute the whole minted token from the config and compare."""
        life = la if typ == "access" else lr
        if nonce[0] is None:
            parts = tok.split(".")
            if len(parts) != 3:
                F.append("%s: token not 3 segments" % tag)
                return None
            try:
                p = json.loads(b64url_dec(parts[1]))
            except Exception:
                F.append("%s: undecodable payload" % tag)
                return None
            jti0 = p.get("jti", "") if isinstance(p, dict) else ""
            if not JTI_RE.fullmatch(jti0):
                F.append("%s: bad jti format %r" % (tag, jti0))
                return None
            nonce[0] = jti0.split("-")[0]
        jti = "%s-%08x" % (nonce[0], mints[0])
        want_hb = b64url(HDR)
        want_pb = b64url(compact({
            "sub": sub, "iss": issuer, "iat": now, "exp": now + life,
            "jti": jti, "typ": typ,
        }).encode("ascii"))
        want_tok = "%s.%s.%s" % (want_hb, want_pb, sign(secret, want_hb, want_pb))
        mints[0] += 1
        if tok != want_tok:
            F.append("%s: token mismatch\n    want %s\n    got  %s"
                     % (tag, want_tok, tok))
        return jti

    try:
        # ---- 1. health
        st, body = req("GET", "/health")
        if st != 200 or body != {"status": "ok"}:
            F.append("%s: /health -> %d %r" % (label, st, body))

        # ---- 2. login user 1
        u1, u2 = names[0], names[1]
        st, body = req("POST", "/login",
                       {"user": u1, "password": users[u1]["password"]})
        if st != 200:
            F.append("%s: /login %s -> %d %r" % (label, u1, st, body))
            return F
        b = body or {}
        a1, r1 = b.get("access_token"), b.get("refresh_token")
        if not isinstance(a1, str) or not isinstance(r1, str) or a1 == r1:
            F.append("%s: /login tokens missing or identical" % label)
            return F
        if (b.get("token_type"), b.get("access_expires_in"),
                b.get("refresh_expires_in")) != ("bearer", la, lr):
            F.append("%s: /login response metadata %r" % (label, b))
            return F
        j_a1 = expect_mint("%s/login/%s/access" % (label, u1), a1, u1, "access")
        j_r1 = expect_mint("%s/login/%s/refresh" % (label, u1), r1, u1, "refresh")
        if j_a1 is None or j_r1 is None:
            F.append("%s: minted login tokens did not match the recomputed contract" % label)
            return F

        # ---- 3. login user 2
        st, body = req("POST", "/login",
                       {"user": u2, "password": users[u2]["password"]})
        if st != 200:
            F.append("%s: /login %s -> %d %r" % (label, u2, st, body))
            return F
        b = body or {}
        a2, r2 = b.get("access_token"), b.get("refresh_token")
        if not isinstance(a2, str) or not isinstance(r2, str):
            F.append("%s: /login tokens missing (user %s)" % (label, u2))
            return F
        j_a2 = expect_mint("%s/login/%s/access" % (label, u2), a2, u2, "access")
        expect_mint("%s/login/%s/refresh" % (label, u2), r2, u2, "refresh")
        if j_a2 is None:
            F.append("%s: minted login tokens did not match the recomputed contract" % label)
            return F

        # ---- 4. /me with u1 access token
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a1})
        want_me = {"sub": u1, "iss": issuer, "iat": now, "exp": now + la,
                   "jti": j_a1, "typ": "access"}
        if st != 200 or body != want_me:
            F.append("%s: /me u1 -> %d %r want %r" % (label, st, body, want_me))

        # ---- 5. /me rejects a refresh token (wrong typ)
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + r1})
        if st != 401 or _code(body) != "invalid_token":
            F.append("%s: /me with refresh -> %d %r" % (label, st, body))

        # ---- 6. rotation: old refresh blacklisted, replay rejected
        st, body = req("POST", "/refresh", {"refresh_token": r1})
        if st != 200:
            F.append("%s: /refresh -> %d %r" % (label, st, body))
            return F
        b = body or {}
        a3, r3 = b.get("access_token"), b.get("refresh_token")
        if not isinstance(a3, str) or not isinstance(r3, str):
            F.append("%s: /refresh tokens missing" % label)
            return F
        expect_mint("%s/rotate/access" % label, a3, u1, "access")
        expect_mint("%s/rotate/refresh" % label, r3, u1, "refresh")
        revocations[j_r1] = "rotated"
        st, body = req("POST", "/refresh", {"refresh_token": r1})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: replay rotated refresh -> %d %r" % (label, st, body))
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a3})
        if st != 200:
            F.append("%s: /me with rotated access -> %d %r" % (label, st, body))
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a1})
        if st != 200:
            F.append("%s: old access after rotation -> %d %r" % (label, st, body))

        # ---- 7. logout u2 access; double logout rejected
        st, body = req("POST", "/logout", {"access_token": a2})
        if st != 200 or body != {"ok": True}:
            F.append("%s: /logout -> %d %r" % (label, st, body))
        else:
            revocations[j_a2] = "logout"
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a2})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: /me after logout -> %d %r" % (label, st, body))
        st, body = req("POST", "/logout", {"access_token": a2})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: double logout -> %d %r" % (label, st, body))

        # ---- 8. logout of a crafted (validly signed) token also revokes it
        c1 = craft(secret, {"sub": u1, "iss": issuer, "iat": now - 10,
                            "exp": now + la, "jti": "craft-logout-1",
                            "typ": "access"})
        st, body = req("POST", "/logout", {"access_token": c1})
        if st != 200:
            F.append("%s: logout crafted -> %d %r" % (label, st, body))
        else:
            revocations["craft-logout-1"] = "logout"
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + c1})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: /me after crafted logout -> %d %r" % (label, st, body))

        # ---- 9. restart: blacklist persists; valid tokens keep working
        stop_service(proc)
        proc = start_service(port)
        old_nonce = nonce[0]
        nonce[0] = None
        mints[0] = 0
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a2})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: post-restart /me revoked -> %d %r" % (label, st, body))
        st, body = req("POST", "/refresh", {"refresh_token": r1})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: post-restart refresh replay -> %d %r" % (label, st, body))
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + c1})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: post-restart crafted revoked -> %d %r" % (label, st, body))
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a1})
        if st != 200:
            F.append("%s: post-restart old access -> %d %r" % (label, st, body))
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + a3})
        if st != 200:
            F.append("%s: post-restart rotated access -> %d %r" % (label, st, body))

        # ---- fresh login after restart: new nonce, seq restarts at 0
        st, body = req("POST", "/login",
                       {"user": u1, "password": users[u1]["password"]})
        if st != 200:
            F.append("%s: post-restart login -> %d %r" % (label, st, body))
            return F
        b = body or {}
        a4, r4 = b.get("access_token"), b.get("refresh_token")
        if not isinstance(a4, str) or not isinstance(r4, str):
            F.append("%s: post-restart login tokens missing" % label)
            return F
        expect_mint("%s/restart/login/access" % label, a4, u1, "access")
        expect_mint("%s/restart/login/refresh" % label, r4, u1, "refresh")
        if nonce[0] == old_nonce:
            F.append("%s: restart reused the same jti nonce (%r)"
                     % (label, nonce[0]))

        # ---- 10. crafted-token matrix (all through /me unless noted)
        cases = [
            ("valid",         {"sub": u1, "iss": issuer, "iat": now - 60,
                               "exp": now + la, "jti": "craft-a", "typ": "access"}, 200, None),
            ("expired",       {"sub": u1, "iss": issuer, "iat": now - 1000,
                               "exp": now - tol - 1, "jti": "craft-b", "typ": "access"},
                             401, "token_expired"),
            ("boundary-exp",  {"sub": u1, "iss": issuer, "iat": now - 500,
                               "exp": now - tol, "jti": "craft-c", "typ": "access"}, 200, None),
            ("future-iat",    {"sub": u1, "iss": issuer, "iat": now + tol + 1,
                               "exp": now + tol + 1 + la, "jti": "craft-d", "typ": "access"},
                             401, "token_not_yet_valid"),
            ("boundary-iat",  {"sub": u1, "iss": issuer, "iat": now + tol,
                               "exp": now + tol + la, "jti": "craft-e", "typ": "access"}, 200, None),
            ("wrong-key",     None, 401, "invalid_token"),
            ("missing-claim", None, 401, "invalid_token"),
            ("wrong-issuer",  None, 401, "invalid_token"),
        ]
        for name, claims, want_st, want_code in cases:
            if name == "wrong-key":
                tok = craft(b"bogus-key-not-the-secret",
                            {"sub": u1, "iss": issuer, "iat": now - 60,
                             "exp": now + la, "jti": "craft-k", "typ": "access"})
            elif name == "missing-claim":
                tok = craft(secret, {"sub": u1, "iss": issuer, "iat": now - 60,
                                     "exp": now + la, "typ": "access"})
            elif name == "wrong-issuer":
                tok = craft(secret, {"sub": u1, "iss": "evil-issuer",
                                     "iat": now - 60, "exp": now + la,
                                     "jti": "craft-i", "typ": "access"})
            else:
                tok = craft(secret, claims)
            st, body = req("GET", "/me", headers={"Authorization": "Bearer " + tok})
            if st != want_st or (want_code is not None and _code(body) != want_code):
                F.append("%s: crafted %s -> %d %r (want %d %s)"
                         % (label, name, st, body, want_st, want_code or "-"))

        # tampered payload: flip the last base64url char of the payload seg
        parts = craft(secret, {"sub": u1, "iss": issuer, "iat": now - 60,
                               "exp": now + la, "jti": "craft-f",
                               "typ": "access"}).split(".")
        parts[1] = parts[1][:-1] + ("B" if parts[1][-1] != "B" else "C")
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + ".".join(parts)})
        if st != 401 or _code(body) != "invalid_token":
            F.append("%s: tampered payload -> %d %r" % (label, st, body))

        # wrong typ both ways
        rcraft = craft(secret, {"sub": u1, "iss": issuer, "iat": now - 5,
                                "exp": now + lr, "jti": "craft-rt1",
                                "typ": "refresh"})
        st, body = req("GET", "/me", headers={"Authorization": "Bearer " + rcraft})
        if st != 401 or _code(body) != "invalid_token":
            F.append("%s: refresh-to-/me -> %d %r" % (label, st, body))
        acraft = craft(secret, {"sub": u1, "iss": issuer, "iat": now - 5,
                                "exp": now + la, "jti": "craft-ac1",
                                "typ": "access"})
        st, body = req("POST", "/refresh", {"refresh_token": acraft})
        if st != 401 or _code(body) != "invalid_token":
            F.append("%s: access-to-/refresh -> %d %r" % (label, st, body))

        # malformed shapes
        for bad in ("abc", "a.b", "aaaa.bbbb.cccc"):
            st, body = req("GET", "/me", headers={"Authorization": "Bearer " + bad})
            if st != 401 or _code(body) != "invalid_token":
                F.append("%s: malformed %r -> %d %r" % (label, bad, st, body))

        # Authorization header issues
        st, body = req("GET", "/me")
        if st != 401 or _code(body) != "invalid_token":
            F.append("%s: /me without auth -> %d %r" % (label, st, body))
        st, body = req("GET", "/me", headers={"Authorization": "Token " + a1})
        if st != 401 or _code(body) != "invalid_token":
            F.append("%s: /me wrong scheme -> %d %r" % (label, st, body))

        # ---- 11. crafted refresh rotation + replay
        cref = craft(secret, {"sub": u1, "iss": issuer, "iat": now - 5,
                              "exp": now + lr, "jti": "craft-refresh-1",
                              "typ": "refresh"})
        st, body = req("POST", "/refresh", {"refresh_token": cref})
        if st != 200:
            F.append("%s: crafted refresh -> %d %r" % (label, st, body))
        else:
            b = body or {}
            if not isinstance(b.get("access_token"), str) \
                    or not isinstance(b.get("refresh_token"), str):
                F.append("%s: crafted refresh tokens missing" % label)
            else:
                expect_mint("%s/craft-refresh/access" % label,
                            b["access_token"], u1, "access")
                expect_mint("%s/craft-refresh/refresh" % label,
                            b["refresh_token"], u1, "refresh")
                revocations["craft-refresh-1"] = "rotated"
        st, body = req("POST", "/refresh", {"refresh_token": cref})
        if st != 401 or _code(body) != "token_revoked":
            F.append("%s: crafted refresh replay -> %d %r" % (label, st, body))

        # ---- 12. /login error matrix
        st, body = req("POST", "/login",
                       {"user": u1, "password": "definitely-wrong"})
        if st != 401 or _code(body) != "invalid_credentials":
            F.append("%s: wrong password -> %d %r" % (label, st, body))
        st, body = req("POST", "/login", {"user": "nobody", "password": "x"})
        if st != 401 or _code(body) != "invalid_credentials":
            F.append("%s: unknown user -> %d %r" % (label, st, body))
        st, body = req("POST", "/login", {"user": u1})
        if st != 400 or _code(body) != "bad_request":
            F.append("%s: missing password -> %d %r" % (label, st, body))
        st, body = req("POST", "/login", {"user": u1, "password": 42})
        if st != 400 or _code(body) != "bad_request":
            F.append("%s: wrong password type -> %d %r" % (label, st, body))
        st, body = req("POST", "/login", "{not json")
        if st != 400 or _code(body) != "bad_request":
            F.append("%s: broken JSON -> %d %r" % (label, st, body))
        st, body = req("GET", "/login")
        if st != 405 or _code(body) != "method_not_allowed":
            F.append("%s: GET /login -> %d %r" % (label, st, body))
        st, body = req("POST", "/no-such-endpoint", {})
        if st != 404 or _code(body) != "not_found":
            F.append("%s: unknown path -> %d %r" % (label, st, body))
        st, body = req("POST", "/refresh", {})
        if st != 400 or _code(body) != "bad_request":
            F.append("%s: /refresh {} -> %d %r" % (label, st, body))
        st, body = req("POST", "/logout", {})
        if st != 400 or _code(body) != "bad_request":
            F.append("%s: /logout {} -> %d %r" % (label, st, body))
        st, body = req("POST", "/login",
                       {"user": u1, "password": users[u1]["password"]},
                       headers={"X-Onyx-Now": "soon"})
        if st != 400 or _code(body) != "bad_request":
            F.append("%s: invalid X-Onyx-Now -> %d %r" % (label, st, body))

        # ---- 13. final blacklist file: exact entry set and reasons
        entries = read_blacklist(F, label)
        if sorted(entries) != sorted(revocations):
            F.append("%s: blacklist entries %r != expected %r"
                     % (label, sorted(entries), sorted(revocations)))
        else:
            for jti, reason in revocations.items():
                if (entries.get(jti) or {}).get("reason") != reason:
                    F.append("%s: blacklist reason for %s is %r, want %r"
                             % (label, jti, entries.get(jti), reason))
    finally:
        stop_service(proc)

    return F


# ---------------------------------------------------------------------------
# entry points
# ---------------------------------------------------------------------------
def read_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def gen_hidden_configs():
    """Three deterministic hidden configs, all different from the visible one."""
    rng = random.Random(61826261)
    names = ["kira", "oden", "suki", "vigo", "mira", "torin", "lira", "hakan"]
    issuers = ["onyx-hub-1", "onyx-hub-2", "onyx-hub-3", "onyx-hub-4"]
    cfgs = []
    for idx in range(3):
        pool = list(names)
        rng.shuffle(pool)
        n_users = rng.randint(2, 4)
        users = {}
        for nm in pool[:n_users]:
            users[nm] = {
                "password": "sp-%04d" % rng.randint(0, 9999),
                "display": "%s %s" % (nm.capitalize(),
                                      rng.choice(["North", "South", "Ring", "Reach"])),
            }
        tol = rng.choice([0, 0, 1, 2, 3])
        la = rng.choice([30, 60, 120, 300, 900])
        lr = rng.choice([600, 1800, 3600, 7200])
        if la <= tol:
            la = tol + 7
        cfgs.append({
            "host": "127.0.0.1",
            "port": 8810 + idx,
            "secret": "%064x" % rng.getrandbits(256),
            "issuer": rng.choice(issuers),
            "clock_skew_sec": tol,
            "lifetimes": {"access_sec": la, "refresh_sec": lr},
            "users": users,
        })
    return cfgs


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "visible"
    failures = []
    if mode == "visible":
        cfg = read_config()
        failures = battery(cfg, "visible", 1712345678)
        print("flow-harness visible: failures=%d" % len(failures))
        for f in failures:
            print("  -", f)
        sys.exit(1 if failures else 0)
    if mode == "hidden":
        cfgs = gen_hidden_configs()
        print("flow-harness hidden: %d generated configs" % len(cfgs))
        for idx, cfg in enumerate(cfgs):
            run_now = 1715000000 + idx * 997
            with open(CONFIG_PATH, "w", encoding="utf-8") as fh:
                json.dump(cfg, fh, indent=2)
            fails = battery(cfg, "hidden-%d" % idx, run_now)
            print("hidden-%d failures=%d (port %d tol %d la %d lr %d users %s)"
                  % (idx, len(fails), cfg["port"], cfg["clock_skew_sec"],
                     cfg["lifetimes"]["access_sec"],
                     cfg["lifetimes"]["refresh_sec"], sorted(cfg["users"])))
            for f in fails:
                print("  -", f)
            failures.extend(fails)
        sys.exit(1 if failures else 0)
    print("unknown mode %r" % mode, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()