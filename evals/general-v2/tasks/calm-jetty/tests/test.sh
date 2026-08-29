#!/bin/bash
# calm-jetty verifier. Exercises every deliverable (including on hidden inputs
# from /tests/hidden), then writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
exec python3 - <<'PYEOF'
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error

failures = []
SERVERS = []
TMP = []


def log(*a):
    print("[verifier]", *a)


def load(path):
    with open(path) as fh:
        return json.load(fh)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def tmp_dir(tag):
    d = tempfile.mkdtemp(prefix="calm_%s_" % tag)
    TMP.append(d)
    return d


# ------------------------------------------------------------------ infra
def start(store_dir, port):
    p = subprocess.Popen(
        [sys.executable, "/app/cloudsvc.py", "--store", store_dir,
         "--port", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = "http://127.0.0.1:%d" % port
    t0 = time.time()
    while time.time() - t0 < 15:
        try:
            with urllib.request.urlopen(base + "/health", timeout=1) as r:
                if r.status == 200:
                    SERVERS.append(p)
                    return base
        except Exception:
            time.sleep(0.2)
    p.kill()
    raise RuntimeError("server on port %d did not come up" % port)


def unwrap(res):
    """Contract (instruction.md) says create_spreadsheet/create_worksheet
    return the JSON *bodies* from the API. Tolerate a (status, body) tuple as
    well, since some clients return both."""
    if isinstance(res, tuple) and len(res) == 2:
        return res
    return 200, res


def http(method, base, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    rq = urllib.request.Request(base + path, data=data, method=method)
    rq.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(rq, timeout=10) as r:
            body = r.read().decode()
            return r.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return e.code, (json.loads(body) if body else {})


def clean_servers():
    for p in SERVERS:
        try:
            p.terminate()
        except Exception:
            pass
    time.sleep(0.3)


# ------------------------------------------------------------- normalize ref
REF_KEYS = ["request_id", "account_id", "handle", "email", "region", "tier",
            "storage_gb", "breach", "active"]


def ref_normalize(raw):
    if not isinstance(raw, dict):
        raw = {}
    reqid = raw.get("request_id")
    reqid = str(reqid) if reqid is not None else ""
    lk = raw.get("lookup") if isinstance(raw.get("lookup"), dict) else {}
    contact = lk.get("contact") if isinstance(lk.get("contact"), dict) else {}
    ent = lk.get("entitlement") if isinstance(lk.get("entitlement"), dict) else {}
    bud = lk.get("budget") if isinstance(lk.get("budget"), dict) else {}
    grd = lk.get("guardrail") if isinstance(lk.get("guardrail"), dict) else {}
    aid = str(lk.get("account_id")) if lk.get("account_id") is not None else ""
    handle = str(lk.get("handle")) if lk.get("handle") is not None else ""
    email = contact.get("email")
    email = email if isinstance(email, str) and email.strip() else None
    region = contact.get("market")
    region = region if isinstance(region, str) else None
    tier = ent.get("tier")
    tier = str(tier).strip().lower() if tier is not None else None
    sg = bud.get("storage_gb")
    try:
        storage_gb = int(sg) if sg is not None else None
    except Exception:
        storage_gb = None
    br = bud.get("breach")
    try:
        breach = int(br) if br is not None else None
    except Exception:
        breach = None
    aware = grd.get("aware")
    active = aware if isinstance(aware, bool) else None
    return {"request_id": reqid, "account_id": aid, "handle": handle,
            "email": email, "region": region, "tier": tier,
            "storage_gb": storage_gb, "breach": breach, "active": active}


# --------------------------------------------------------------- 1. normalize
def check_normalize():
    try:
        mod = load_module("/app/normalize_rpc.py", "normalize")
    except Exception as e:
        failures.append("rpc: cannot import module: %r" % e)
        return
    fun = getattr(mod, "normalize_rpc", None)
    if not callable(fun):
        failures.append("rpc: no callable normalize_rpc")
        return
    if not os.path.exists("/app/sample_rpc.json"):
        failures.append("rpc: missing fixture sample_rpc.json")
        return
    sample = load("/app/sample_rpc.json")
    try:
        got = fun(sample)
    except Exception as e:
        failures.append("rpc: normalize_rpc(sample) raised %r" % e)
        return
    if not isinstance(got, list) or len(got) != len(sample):
        failures.append("rpc: normalize_rpc(sample) length mismatch")
        return
    if not os.path.exists("/app/rpc_normalized.json"):
        failures.append("rpc: missing /app/rpc_normalized.json")
    else:
        norm = load("/app/rpc_normalized.json")
        js = norm.get("cases") if isinstance(norm, dict) else norm
        if js != got:
            failures.append("rpc: rpc_normalized.json != normalize_rpc(sample)")
        if js != [ref_normalize(x) for x in sample]:
            failures.append("rpc: rpc_normalized.json != reference schema")

    if not os.path.exists("/tests/hidden/rpc_cases.json"):
        failures.append("rpc: missing hidden rpc_cases.json")
        return
    hidden = load("/tests/hidden/rpc_cases.json")
    try:
        out = fun(hidden)
    except Exception as e:
        failures.append("rpc: normalize_rpc(hidden) raised %r" % e)
        return
    if len(out) != len(hidden):
        failures.append("rpc: hidden count mismatch")
        return
    for i, raw in enumerate(hidden):
        doc = out[i]
        if not isinstance(doc, dict):
            failures.append("rpc: hidden case %d not a dict" % i)
            continue
        if list(doc.keys()) != REF_KEYS:
            failures.append("rpc: hidden case %d keys %r != %r" % (i, list(doc.keys()), REF_KEYS))
        want = ref_normalize(raw)
        if doc != want:
            failures.append("rpc: hidden case %d mismatch\n  want %r\n  got  %r" % (i, want, doc))


# --------------------------------------------------------------- 2. sheets
def check_sheets():
    if not os.path.exists("/app/sheets_client.py"):
        failures.append("sheets: missing /app/sheets_client.py")
        return
    mod = load_module("/app/sheets_client.py", "sheets")
    create_sp = getattr(mod, "create_spreadsheet", None)
    create_ws = getattr(mod, "create_worksheet", None)
    if not callable(create_sp) or not callable(create_ws):
        failures.append("sheets: missing create_spreadsheet/create_worksheet")
        return

    if not os.path.exists("/app/sheet_ids.json"):
        failures.append("sheets: missing /app/sheet_ids.json")
    else:
        sidf = load("/app/sheet_ids.json")
        sp_id = sidf.get("spreadsheet_id")
        ws_id = sidf.get("sheet_id")
        if not sp_id or not ws_id:
            failures.append("sheets: sheet_ids.json missing id fields")
        else:
            base = start("/app/store", 8702)
            st, doc = http("GET", base, "/sheets/v1/%s" % sp_id)
            if st != 200 or doc.get("spreadsheet_id") != sp_id:
                failures.append("sheets: live spreadsheet_id %r not found" % sp_id)
            st2, doc2 = http("GET", base, "/sheets/v1/%s/sheets/%s" % (sp_id, ws_id))
            if st2 != 200 or not doc2.get("exists"):
                failures.append("sheets: live worksheet %r missing" % ws_id)

    # hidden scenario: client must generalize to arbitrary names
    if not os.path.exists("/tests/hidden/sheets_case.json"):
        failures.append("sheets: missing hidden sheets_case.json")
        return
    hcase = load("/tests/hidden/sheets_case.json")
    d = tmp_dir("sheets")
    shutil.copy("/app/store/sheets.json", os.path.join(d, "sheets.json"))
    base = start(d, 8707)
    try:
        st, sp = unwrap(create_sp(base, hcase["spreadsheet_name"]))
        if st not in (200, 201) or not (isinstance(sp, dict) and sp.get("spreadsheet_id")):
            failures.append("sheets: hidden create_spreadsheet failed %s %r" % (st, sp))
            return
        sid = sp["spreadsheet_id"]
        st, ws = unwrap(create_ws(base, sid, hcase["worksheet_title"]))
        if st not in (200, 201) or not (isinstance(ws, dict) and ws.get("sheet_id")):
            failures.append("sheets: hidden create_worksheet failed %s %r" % (st, ws))
            return
        st, doc = http("GET", base, "/sheets/v1/%s/sheets/%s" % (sid, ws["sheet_id"]))
        if st != 200 or not doc.get("exists"):
            failures.append("sheets: hidden created resource not usable")
        elif doc.get("title") != hcase["worksheet_title"]:
            failures.append("sheets: hidden title mismatch %r" % doc.get("title"))
    except Exception as e:
        failures.append("sheets: hidden execution raised %r" % e)


# --------------------------------------------------------------- 3. delete
def check_users():
    if not os.path.exists("/app/delete_users.py"):
        failures.append("users: missing /app/delete_users.py")
        return
    mod = load_module("/app/delete_users.py", "users")
    del_all = getattr(mod, "delete_targets", None)
    list_acc = getattr(mod, "list_accounts", None)
    if not callable(del_all) or not callable(list_acc):
        failures.append("users: missing delete_targets/list_accounts")
        return
    seed_all = load("/app/accounts_seed.json")
    targets = load("/app/delete_targets.json")["targets"]
    expected = sorted(set(a["user_id"] for a in seed_all) - set(targets))

    if not os.path.exists("/app/users_remaining.json"):
        failures.append("users: missing /app/users_remaining.json")
    else:
        ur = load("/app/users_remaining.json")
        rem = ur.get("accounts_remaining") if isinstance(ur, dict) else ur
        ids = sorted(a["user_id"] for a in rem)
        if ids != expected:
            failures.append("users: users_remaining.json ids %r != expected %r" % (ids, expected))

    base = start("/app/store", 8703)
    _, body = http("GET", base, "/identity/v2/accounts")
    live_ids = sorted(a["user_id"] for a in body.get("accounts", []))
    if live_ids != expected:
        failures.append("users: live store %r != expected %r" % (live_ids, expected))
    for uid in targets:
        st, _ = http("GET", base, "/identity/v2/accounts/" + uid)
        if st != 404:
            failures.append("users: live target %r still present" % uid)
    for uid in expected[:2]:
        st, _ = http("GET", base, "/identity/v2/accounts/" + uid)
        if st != 200:
            failures.append("users: live survivor %r deleted" % uid)

    if not os.path.exists("/tests/hidden/identity_seed.json"):
        failures.append("users: missing hidden identity_seed.json")
        return
    hs = load("/tests/hidden/identity_seed.json")
    htargets = hs["targets"]
    hexp = sorted(set(a["user_id"] for a in hs["accounts"]) - set(htargets))
    d = tmp_dir("users")
    with open(os.path.join(d, "identity.json"), "w") as fh:
        json.dump({"accounts": hs["accounts"]}, fh)
    hbase = start(d, 8704)
    try:
        removed = set(del_all(hbase, htargets))
    except Exception as e:
        failures.append("users: hidden delete_targets raised %r" % e)
        return
    _, body = http("GET", hbase, "/identity/v2/accounts")
    hid_ids = sorted(a["user_id"] for a in body.get("accounts", []))
    if hid_ids != hexp:
        failures.append("users: hidden remaining %r != expected %r" % (hid_ids, hexp))
    if removed != set(htargets):
        failures.append("users: hidden removed %r != targets %r" % (sorted(removed), sorted(htargets)))
    for t in htargets:
        st, _ = http("GET", hbase, "/identity/v2/accounts/" + t)
        if st != 404:
            failures.append("users: hidden target %r still present" % t)
    for uid in hexp[:2]:
        st, _ = http("GET", hbase, "/identity/v2/accounts/" + uid)
        if st != 200:
            failures.append("users: hidden survivor %r deleted" % uid)


# ------------------------------------------------------------------ blob
def check_blob_policy():
    if not os.path.exists("/app/bucket_policy.json"):
        failures.append("blob: missing /app/bucket_policy.json")
        return
    try:
        pol = load("/app/bucket_policy.json")
    except Exception as e:
        failures.append("blob: bucket_policy.json unreadable: %r" % e)
        return
    stmts = pol.get("Statement", [])
    if isinstance(stmts, dict):
        stmts = [stmts]
    ok = False
    for s in stmts if isinstance(stmts, list) else []:
        if not isinstance(s, dict) or s.get("Effect") != "Allow":
            continue
        prin = s.get("Principal")
        if not (prin == "*" or (isinstance(prin, dict) and prin.get("AWS") == "*")):
            continue
        act = s.get("Action")
        acts = act if isinstance(act, list) else ([act] if act else [])
        if not any(a == "*" or (isinstance(a, str) and a.lower() == "s3:getobject") for a in acts):
            continue
        res = s.get("Resource")
        ress = res if isinstance(res, list) else ([res] if res else [])
        if any(isinstance(r, str) and "reports" in r and "*" in r for r in ress):
            ok = True
    if not ok:
        failures.append("blob: bucket_policy.json does not grant public GetObject on reports/*")

    base = start("/app/store", 8705)
    for obj in ("2024-boardings.parquet", "2025-forecast.parquet"):
        st, body = http("GET", base, "/blob/v2/buckets/reports/access?object=%s" % obj)
        if st != 200 or not body.get("allowed"):
            failures.append("blob: live reports not public (%s %r)" % (st, body))

    # hidden: re-apply the policy file and check it works on a fresh object list
    if not os.path.exists("/tests/hidden/blob_store.json"):
        failures.append("blob: missing hidden blob_store.json")
        return
    d = tmp_dir("blob")
    with open(os.path.join(d, "blob.json"), "w") as fh:
        json.dump(load("/tests/hidden/blob_store.json"), fh)
    hbase = start(d, 8706)
    st, _ = http("PUT", hbase, "/blob/v2/buckets/reports/policy",
                 payload=load("/app/bucket_policy.json"))
    if st != 200:
        failures.append("blob: hidden policy re-apply status %d" % st)
    for obj in ("q3-2026-ridership.csv", "farebox-trend.json"):
        st, body = http("GET", hbase, "/blob/v2/buckets/reports/access?object=%s" % obj)
        if st != 200 or not body.get("allowed"):
            failures.append("blob: hidden reports not public after re-apply (%s)" % st)


print("running checks ...")
reward = 0

try:
    check_normalize()
    check_sheets()
    check_users()
    check_blob_policy()

    reward = 0 if failures else 1
except Exception as e:
    failures.append("verifier crashed: %r" % e)
    reward = 0
finally:
    clean_servers()
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write(str(reward) + "\n")

print("reward=%d failures=%d" % (reward, len(failures)))
for f in failures[:60]:
    print("  -", f)
PYEOF