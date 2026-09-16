#!/usr/bin/env python3
"""jib-weir verifier.

Starts the agent's catalogue API server from the deliverable /app/start.sh on
four datasets (the visible one plus three hidden cases), asserts the full HTTP
contract (cursor pagination, typed 400 error bodies, 404s, persistence across
POST/PATCH, query validation), and checks the delivered OpenAPI document:
structural validity, $ref resolution, exact route coverage, status codes,
request-body schema derived from the zod validation, a live server that serves
exactly the delivered bytes at GET /openapi.json, and that no documented path
is a dead route.
"""
import http.client
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

VISIBLE = "/app/data/media.json"
HIDDEN_GLOB = "/tests/hidden"
PORT_BASE = {"visible": 9450, "case1": 9451, "case2": 9452, "case3": 9453}
LIMITS = {48: 7, 41: 5, 23: 11, 97: 23}  # page size per dataset size
PIDFILE = "/tmp/jib-weir-server.pid"
START_SH = "/app/start.sh"
OPENAPI_FILE = "/app/openapi.json"
CURSOR_RE = re.compile(r"^[A-Za-z0-9._~=-]{1,300}$")

failures = []
logtail_limit = 25


def fail(msg):
    failures.append(msg)


def tail(path, n=logtail_limit):
    try:
        with open(path, "r", errors="replace") as fh:
            lines = fh.readlines()
        return "".join(lines[-n:])
    except OSError:
        return "<no log>"


def req(method, url, body=None):
    """Return (status, parsed json-or-text, raw bytes). Always catches errors."""
    data = None
    headers = {}
    if body is not None:
        data = body if isinstance(body, (bytes, bytearray)) else json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            blob = resp.read()
            return resp.status, json.loads(blob) if blob else None, blob
    except urllib.error.HTTPError as exc:
        blob = exc.read()
        try:
            return exc.code, json.loads(blob) if blob else None, blob
        except Exception:
            return exc.code, None, blob
    except Exception as exc:
        raise RuntimeError("http %s %s failed: %s" % (method, url, exc))


def health_ok(port):
    try:
        status, _body, _raw = req("GET", "http://127.0.0.1:%d/health" % port)
        return status == 200
    except Exception:
        return False


def stop_previous():
    try:
        with open(PIDFILE) as fh:
            pid = int(fh.read().strip())
    except (OSError, ValueError):
        return
    try:
        os.kill(pid, signal.SIGTERM)
        for _ in range(10):
            try:
                os.kill(pid, 0)
            except OSError:
                return
            time.sleep(0.2)
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def start_server(port, data_path, case):
    stop_previous()
    log_path = "/tmp/jibw-%s.log" % case
    with open(log_path, "w") as fh:
        proc = subprocess.Popen(
            ["bash", START_SH, str(port), data_path],
            stdout=fh,
            stderr=subprocess.STDOUT,
        )
    deadline = time.time() + 90
    while time.time() < deadline:
        if health_ok(port):
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
            # The start.sh contract requires the server pid in $PIDFILE. Give a
            # conforming script a short window to write it (a correct script
            # writes it before printing READY), then require it to name a live
            # process. Without this, a start.sh that never writes the pidfile
            # still passes every HTTP check because each case uses a fresh port.
            pid_ok = False
            for _ in range(40):
                try:
                    with open(PIDFILE) as fh:
                        pid = int(fh.read().strip())
                    os.kill(pid, 0)
                    pid_ok = True
                    break
                except (OSError, ValueError):
                    time.sleep(0.75)
            if not pid_ok:
                raise RuntimeError(
                    "%s: server is healthy but %s does not name a live pid "
                    "(start.sh must record the server pid per the contract); "
                    "log tail:\n%s" % (case, PIDFILE, tail(log_path))
                )
            return proc
        if proc.poll() is not None:
            raise RuntimeError(
                "%s: %s exited rc=%s; log tail:\n%s"
                % (case, START_SH, proc.returncode, tail(log_path))
            )
        time.sleep(0.5)
    raise RuntimeError("%s: server never became healthy; log tail:\n%s"
                       % (case, tail(log_path)))


def load_dataset(path):
    with open(path) as fh:
        raw = json.load(fh)
    if not isinstance(raw, dict) or not isinstance(raw.get("items"), list):
        raise ValueError("%s: dataset must be {\"items\": [...]}" % path)
    items = []
    for idx, item in enumerate(raw["items"], 1):
        clone = dict(item)
        clone["id"] = idx
        items.append(clone)
    return items


# ---------------------------------------------------------------------------
def check_pagination(base, items):
    limit = LIMITS.get(len(items), 7)
    ordered = sorted(items, key=lambda it: (it["year"], it["id"]))
    seen = []
    cursor = None
    step = 0
    while True:
        step += 1
        if step > len(items) + 4:
            fail("pagination walk did not terminate")
            break
        params = {"limit": str(limit)}
        if cursor is not None:
            params["cursor"] = cursor
        url = base + "/api/media?" + urllib.parse.urlencode(params)
        status, body, _raw = req("GET", url)
        if status != 200:
            fail("list returned %d (want 200)" % status)
            return
        if not isinstance(body, dict) or set(body) != {"items", "next_cursor", "total"}:
            fail("list body keys must be exactly items/next_cursor/total: %r" % (body,))
            return
        page = body["items"]
        if not isinstance(page, list) or len(page) > limit:
            fail("page longer than limit %d" % limit)
            return
        if body["next_cursor"] is not None:
            if not isinstance(body["next_cursor"], str) or not CURSOR_RE.match(body["next_cursor"]):
                fail("next_cursor not a URL-safe opaque token: %r" % (body["next_cursor"],))
                return
        if body["total"] != len(items):
            fail("total=%r want %d" % (body["total"], len(items)))
            return
        seen.extend(page)
        if body["next_cursor"] is None:
            break
        cursor = body["next_cursor"]

    if len(seen) != len(items):
        fail("walked %d items, dataset has %d" % (len(seen), len(items)))
        return
    got_keys = [(it["year"], it["id"]) for it in seen]
    want_keys = [(it["year"], it["id"]) for it in ordered]
    if got_keys != want_keys:
        fail("page walk is not in (year, id) ascending order")
        return
    ids = [it["id"] for it in seen]
    if len(set(ids)) != len(ids):
        fail("page walk revisited an item (duplicate id across pages)")


def check_single_item(base, items):
    n = len(items)
    for probe_id in (1, n):
        status, body, _raw = req("GET", "%s/api/media/%d" % (base, probe_id))
        if status != 200:
            fail("GET /api/media/%d returned %d (want 200)" % (probe_id, status))
            continue
        want = next(it for it in items if it["id"] == probe_id)
        got = body.get("item") if isinstance(body, dict) else None
        if got != want:
            fail("GET /api/media/%d body mismatch\n got %r\nwant %r" % (probe_id, got, want))

    status, body, _raw = req("GET", "%s/api/media/%d" % (base, n + 5000))
    if status != 404 or not (isinstance(body, dict) and body.get("error", {}).get("code") == "not_found"):
        fail("missing id must 404 with error.code=not_found, got %d %r" % (status, body))

    for bad in ("abc", "1.5", "-3", "0"):
        status, body, _raw = req("GET", "%s/api/media/%s" % (base, bad))
        if status != 400:
            fail("GET /api/media/%s must 400 (non-positive-integer id), got %d" % (bad, status))


def check_create(base, items):
    n = len(items)
    seed = items[-1]
    payload = {
        "title": seed["title"] + " (reissue)",
        "year": seed["year"],
        "rating": seed["rating"],
        "medium": seed["medium"],
        "tags": seed["tags"],
    }
    status, body, _raw = req("POST", base + "/api/media", body=payload)
    if status != 201:
        fail("valid POST returned %d (want 201): %r" % (status, body))
        return
    created = body.get("item") if isinstance(body, dict) else None
    if not isinstance(created, dict):
        fail("POST 201 body must be {\"item\": {...}}")
        return
    if not isinstance(created["id"], int) or created["id"] <= n:
        fail("server must assign a fresh id > %d, got %r" % (n, created["id"]))
        return
    for key in ("title", "year", "rating", "medium", "tags"):
        if created.get(key) != payload[key]:
            fail("POST echo field %r wrong: got %r want %r" % (key, created.get(key), payload[key]))
            return
    new_id = created["id"]
    status, body, _raw = req("GET", "%s/api/media/%d" % (base, new_id))
    if status != 200 or body.get("item", {}).get("title") != payload["title"]:
        fail("created item is not retrievable afterwards")

    probes = [
        ({}, "title"),
        ({"title": "", "year": 2000, "rating": 1, "medium": "film"}, "title"),
        ({"title": "x", "year": 1899, "rating": 1, "medium": "film"}, "year"),
        ({"title": "x", "year": 2101, "rating": 1, "medium": "film"}, "year"),
        ({"title": "x", "year": 2000, "rating": -1, "medium": "film"}, "rating"),
        ({"title": "x", "year": 2000, "rating": 101, "medium": "film"}, "rating"),
        ({"title": "x", "year": 2000, "rating": 1, "medium": "podcast"}, "medium"),
        ({"title": "x", "year": 2000, "rating": 1, "medium": "film",
          "tags": ["a", "b", "c", "d", "e", "f"]}, "tags"),
        ({"title": "x" * 101, "year": 2000, "rating": 1, "medium": "film"}, "title"),
        ({"title": "x", "year": 2000, "rating": 1, "medium": "film", "director": "nope"}, None),
    ]
    for payload, field in probes:
        status, body, _raw = req("POST", base + "/api/media", body=payload)
        problem = None
        if status != 400:
            problem = "status %d (want 400)" % status
        elif not isinstance(body, dict) or body.get("error", {}).get("code") != "validation_failed":
            problem = "error envelope missing (code=validation_failed)"
        elif not isinstance(body.get("error", {}).get("details"), list) or not body["error"]["details"]:
            problem = "no per-field details array"
        elif field is not None and not any(
            isinstance(d, dict) and field in (d.get("path") or []) for d in body["error"]["details"]
        ):
            problem = "no detail entry points at field %r (details=%r)" % (field, body["error"]["details"])
        if problem:
            fail("POST probe %r -> %s" % (payload, problem))

    # malformed JSON must still produce a JSON 400, not an HTML error.
    port = int(base.rsplit(":", 1)[1])
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    try:
        conn.request("POST", "/api/media", body=b"{ not json", headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        blob = resp.read()
        conn.close()
        if resp.status != 400:
            fail("malformed JSON body -> status %d (want 400)" % resp.status)
        else:
            try:
                parsed = json.loads(blob)
                if not isinstance(parsed, dict) or "error" not in parsed:
                    fail("malformed JSON body -> 400 without error envelope")
            except Exception:
                fail("malformed JSON body -> non-JSON 400 body")
    except Exception as exc:
        fail("malformed JSON probe failed: %r" % exc)


def check_patch(base):
    # need a known id: create one
    status, body, _raw = req("POST", base + "/api/media",
                              body={"title": "patch target", "year": 2001,
                                    "rating": 50, "medium": "short"})
    if status != 201:
        fail("patch setup POST failed: %d %r" % (status, body))
        return
    target = body["item"]["id"]

    status, body, _raw = req("PATCH", "%s/api/media/%d" % (base, target),
                              body={"year": 1999, "rating": 12, "tags": ["x"]})
    if status != 200:
        fail("valid PATCH returned %d (want 200): %r" % (status, body))
        return
    item = body.get("item")
    if not (item and item["year"] == 1999 and item["rating"] == 12 and item["tags"] == ["x"]):
        fail("PATCH did not apply all fields: %r" % (item,))
        return
    status, body, _raw = req("GET", "%s/api/media/%d" % (base, target))
    if body.get("item", {}).get("year") != 1999:
        fail("PATCH change not visible on a later GET")

    for payload in ({}, {"foo": 1}, {"title": ""}, {"year": 2101}, {"tags": ["a", "b", "c", "d", "e", "f"]}):
        status, body, _raw = req("PATCH", "%s/api/media/%d" % (base, target), body=payload)
        if status != 400:
            fail("invalid PATCH %r -> %d (want 400)" % (payload, status))

    status, body, _raw = req("PATCH", "%s/api/media/%d" % (base, 9999999), body={"year": 2000})
    if status != 404:
        fail("PATCH on missing id -> %d (want 404)" % status)
    status, body, _raw = req("PATCH", "%s/api/media/abc" % base, body={"year": 2000})
    if status != 400:
        fail("PATCH with non-integer id -> %d (want 400)" % status)


def check_query_validation(base):
    for q in ("limit=101", "limit=0", "limit=xyz", "limit=-5"):
        status, body, _raw = req("GET", base + "/api/media?" + q)
        if status != 400:
            fail("GET /api/media?%s -> %d (want 400)" % (q, status))


# ---------------------------------------------------------------------------
def resolve_ref(doc, node):
    seen = 0
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if not ref.startswith("#/"):
            raise ValueError("external ref not allowed: %r" % ref)
        parts = ref[2:].split("/")
        cur = doc
        for part in parts:
            if not isinstance(cur, dict) or part not in cur:
                raise ValueError("dangling $ref %r" % ref)
            cur = cur[part]
        node = cur
        seen += 1
        if seen > 50:
            raise ValueError("$ref cycle")
    return node


def check_openapi_document():
    if not os.path.exists(OPENAPI_FILE):
        fail("deliverable %s missing" % OPENAPI_FILE)
        return
    try:
        with open(OPENAPI_FILE) as fh:
            doc = json.load(fh)
    except Exception as exc:
        fail("%s does not parse: %s" % (OPENAPI_FILE, exc))
        return

    if not str(doc.get("openapi", "")).startswith("3.0"):
        fail("openapi version must be 3.0.x, got %r" % doc.get("openapi"))
    info = doc.get("info") or {}
    if not isinstance(info.get("title"), str) or not info["title"].strip():
        fail("info.title missing")
    if not isinstance(info.get("version"), str) or not info["version"].strip():
        fail("info.version missing")

    paths = doc.get("paths")
    if not isinstance(paths, dict) or not paths:
        fail("paths must be a non-empty object")
        return

    required_ops = {
        ("/api/media", "get"): ["200"],
        ("/api/media", "post"): ["201", "400"],
        ("/api/media/{id}", "get"): ["200", "400", "404"],
        ("/api/media/{id}", "patch"): ["200", "400", "404"],
    }
    for (path, method), codes in required_ops.items():
        operation = (paths.get(path) or {}).get(method)
        if not isinstance(operation, dict):
            fail("openapi must document %s %s" % (method.upper(), path))
            continue
        responses = operation.get("responses")
        if not isinstance(responses, dict):
            fail("%s %s has no responses object" % (method.upper(), path))
            continue
        for code in codes:
            if str(code) not in responses:
                fail("%s %s must document response %s" % (method.upper(), path, code))
        for code, resp in responses.items():
            if not isinstance(resp, dict) or not (isinstance(resp.get("description"), str) or resp.get("content")):
                fail("%s %s response %s malformed" % (method.upper(), path, code))

    # POST body schema must reflect the enforced validation.
    post_body = (paths["/api/media"]["post"].get("requestBody") or {}).get("content") or {}
    if "application/json" not in post_body:
        fail("POST /api/media requestBody must accept application/json")
    else:
        try:
            schema = resolve_ref(doc, post_body["application/json"].get("schema"))
        except ValueError as exc:
            fail("POST body schema: %s" % exc)
            schema = None
        if isinstance(schema, dict):
            if schema.get("type") != "object":
                fail("POST body schema must be an object")
            required = list(schema.get("required") or [])
            if set(required) != {"title", "year", "rating", "medium"}:
                fail("POST body schema required must be exactly "
                     "[title, year, rating, medium], got %r" % (required,))
            props = schema.get("properties") or {}
            for field in ("title", "year", "rating", "medium", "tags"):
                if field not in props:
                    fail("POST body schema missing property %r" % field)
        else:
            fail("unresolvable POST body schema")

    # every $ref everywhere must resolve
    def walk(node):
        if isinstance(node, dict):
            if "$ref" in node:
                try:
                    resolve_ref(doc, node)
                except ValueError as exc:
                    fail("openapi: %s" % exc)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(doc)

    # the zod->openapi generator must be what produced the document
    found_gen = False
    for root, _dirs, files in os.walk("/app"):
        if "node_modules" in root or "dist" in root or "/opt" in root:
            continue
        for name in files:
            if name.endswith(".ts"):
                try:
                    text = open(os.path.join(root, name), encoding="utf8", errors="replace").read()
                except OSError:
                    continue
                if "zod-to-openapi" in text.replace(" ", ""):
                    found_gen = True
    if not found_gen:
        fail("no TypeScript source under /app imports the zod-to-openapi generator "
             "(the OpenAPI document must be generated from the zod schemas)")


def check_live_openapi(base):
    status, _body, raw = req("GET", base + "/openapi.json")
    if status != 200:
        fail("GET /openapi.json -> %d (want 200)" % status)
        return
    try:
        with open(OPENAPI_FILE, "rb") as fh:
            on_disk = fh.read()
    except OSError as exc:
        fail("cannot read %s: %s" % (OPENAPI_FILE, exc))
        return
    if raw != on_disk:
        # Re-serialization with identical content is tolerated; a different
        # document is not.
        try:
            identical = json.loads(raw) == json.loads(on_disk)
        except Exception:
            identical = False
        if not identical:
            fail("GET /openapi.json served document differs from the delivered "
                 "%s file (the served doc must be the emitted one)" % OPENAPI_FILE)

    # every documented path+method must be a real route (not 404)
    try:
        doc = json.load(open(OPENAPI_FILE))
    except Exception:
        return
    for path, operations in (doc.get("paths") or {}).items():
        if "{" in path:
            continue
        for method in operations:
            if method not in ("get", "post", "put", "patch", "delete"):
                continue
            method = method.upper()
            url = base + path
            try:
                if method == "GET":
                    status, _b, _r = req("GET", url)
                else:
                    status, _b, _r = req(method, url, body={})
            except RuntimeError as exc:
                fail("route probe %s %s failed: %s" % (method, path, exc))
                continue
            if status == 404:
                fail("documented route %s %s returns 404 (documented but not "
                     "implemented)" % (method, path))


# ---------------------------------------------------------------------------
def run_case(name, data_path):
    port = PORT_BASE.get(name, 9462)
    base = "http://127.0.0.1:%d" % port
    try:
        items = load_dataset(data_path)
    except Exception as exc:
        fail("%s: dataset unusable: %s" % (name, exc))
        return
    proc = None
    try:
        start_server(port, data_path, name)
        check_pagination(base, items)
        check_single_item(base, items)
        check_create(base, items)
        check_patch(base)
        check_query_validation(base)
    except RuntimeError as exc:
        fail(str(exc))
    finally:
        stop_previous()


def main():
    if not os.path.exists(START_SH):
        fail("deliverable %s missing" % START_SH)
    elif not os.access(START_SH, os.X_OK):
        fail("deliverable %s is not executable" % START_SH)

    if not os.path.exists(VISIBLE):
        fail("visible dataset %s missing" % VISIBLE)

    cases = [("visible", VISIBLE)]
    if os.path.isdir(HIDDEN_GLOB):
        for case in sorted(os.listdir(HIDDEN_GLOB)):
            data = os.path.join(HIDDEN_GLOB, case, "data.json")
            if os.path.isfile(data):
                cases.append((case, data))
    hidden_count = len(cases) - 1
    if hidden_count < 2:
        fail("verifier needs >= 2 hidden datasets, found %d" % hidden_count)

    openapi_checked = False
    for name, data in cases:
        run_case(name, data)
        if name == "visible":
            check_openapi_document()
            port = PORT_BASE["visible"]
            try:
                start_server(port, VISIBLE, "visible")
                check_live_openapi("http://127.0.0.1:%d" % port)
            except RuntimeError as exc:
                fail(str(exc))
            finally:
                stop_previous()
            openapi_checked = True

    if failures:
        print("jib-weir VERIFIER FAILURES (%d):" % len(failures))
        for line in failures:
            print("  - " + line)
        return 1
    print("jib-weir: ALL CHECKS PASSED (%d datasets)" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main())