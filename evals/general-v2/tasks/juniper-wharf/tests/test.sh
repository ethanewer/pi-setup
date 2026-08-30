#!/bin/bash
# juniper-wharf verifier (executes-deliverable). Runs as root after the agent
# finishes; /tests is mounted read-only. Executes EVERY deliverable:
#   * /app/service.proto  -> protoc codegen + live gRPC round-trip
#   * /app/certcheck.py   -> visible cert + each hidden scenario cert
#   * /app/download.py    -> visible S3 endpoint + fresh hidden object servers
#   * /app/creds_probe.py -> visible control head + fresh hidden control heads
# Writes a numeric reward to /logs/verifier/reward.txt (0 on any crash path).
set -u
mkdir -p /logs/verifier
# Crash-proofing: if the python verifier dies for any reason (uncaught
# exception, timeout, kill), still write a 0 reward so a reward is always
# recorded. The python body overwrites this file with the real result when it
# completes normally.
_cleanup() {
    if [ ! -s /logs/verifier/reward.txt ]; then
        echo 0 > /logs/verifier/reward.txt
    fi
}
trap _cleanup EXIT
exec python3 - <<'PY'
import hashlib, json, os, subprocess, sys, tempfile, time
import urllib.request
from concurrent import futures

import grpc as _grpc
import pandas as pd

HID = "/tests/hidden"
fail = []
def note(m): fail.append(m)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def urlok(port):
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=2) as r:
            return r.status == 200
    except Exception:
        return False


def wait_up(port):
    for _ in range(50):
        if urlok(port):
            return True
        time.sleep(0.2)
    return False


# --------------------------------------------------------------------- proto round-trip helpers
# The instruction contract fixes only the three MESSAGE CLASS names; field names
# inside the messages are the agent's choice ("sensible fields"). The round-trip
# below therefore adapts to whatever schema the generated module exposes instead
# of assuming a fixed {dock_id,vessel,berth} shape.

def proto_fill(msg, tag):
    """Give every scalar singular field a deterministic non-default value, so a
    live gRPC call actually serialises data under the agent's own schema."""
    for fd in msg.DESCRIPTOR.fields:
        if fd.is_repeated:
            continue                      # skip repeated / map fields
        if fd.type in (fd.TYPE_MESSAGE, fd.TYPE_ENUM):
            continue
        n = fd.name
        if fd.type == fd.TYPE_BOOL:
            val = True
        elif fd.type in (fd.TYPE_FLOAT, fd.TYPE_DOUBLE):
            val = 1.25
        elif fd.type in (fd.TYPE_STRING, fd.TYPE_BYTES):
            val = "v" + tag + "-" + n if fd.type == fd.TYPE_STRING else ("v" + tag + "-" + n).encode()
        else:
            val = 77
        try:
            setattr(msg, n, val)
        except Exception:
            pass


def proto_echo(src, dst):
    """Copy scalar values from src into same-named, same-typed scalar fields of
    dst, so the server can echo whatever the client sent without assuming a
    fixed field-name contract."""
    sby = src.DESCRIPTOR.fields_by_name
    for fd in dst.DESCRIPTOR.fields:
        sfd = sby.get(fd.name)
        if sfd is None or sfd.type != fd.type:
            continue
        if fd.is_repeated or sfd.is_repeated or fd.type == fd.TYPE_MESSAGE:
            continue
        try:
            setattr(dst, fd.name, getattr(src, fd.name))
        except Exception:
            pass


# ====================================================================== presence
for d in ["/app/service.proto", "/app/certcheck.py", "/app/download.py", "/app/creds_probe.py"]:
    if not os.path.exists(d):
        note("missing deliverable: " + d)
    elif not os.access(d, os.R_OK):
        note("deliverable not readable: " + d)

# ====================================================================== 1. proto
def check_proto():
    if not os.path.exists("/app/service.proto"):
        return
    text = open("/app/service.proto").read()
    for tok in ["service WharfRegistry", "rpc Claim", "rpc Renew",
                "message DockRequest", "message Receipt", "message Renewal"]:
        if tok not in text:
            note("proto lacks %r" % tok)
    gen = tempfile.mkdtemp(prefix="vgen_")
    r = run([sys.executable, "-m", "grpc_tools.protoc", "-I/app",
             "--python_out=" + gen, "--grpc_python_out=" + gen, "/app/service.proto"])
    if r.returncode != 0:
        note("protoc failed: " + r.stderr.strip())
        return
    if not (os.path.exists(os.path.join(gen, "service_pb2.py"))
            and os.path.exists(os.path.join(gen, "service_pb2_grpc.py"))):
        note("protoc did not emit both binding modules")
        return
    sys.path.insert(0, gen)
    import service_pb2 as pb
    import service_pb2_grpc as pg
    if not hasattr(pg, "WharfRegistryStub"):
        note("no WharfRegistryStub in generated grpc module")
    for cls in ("DockRequest", "Receipt", "Renewal"):
        if not hasattr(pb, cls):
            note("no message %s in generated pb2" % cls)
    if all(hasattr(pb, c) for c in ("DockRequest", "Receipt", "Renewal")):
        for cls in ("DockRequest", "Receipt", "Renewal"):
            if not len(getattr(pb, cls).DESCRIPTOR.fields):
                note("message %s declares no fields (instruction requires sensible fields)" % cls)
    # live round-trip: server implementing the agent's schema (schema-adaptive:
    # no assumption about which field names the agent chose)
    srv = _grpc.server(futures.ThreadPoolExecutor(max_workers=2))

    class Servicer(pg.WharfRegistryServicer):
        def Claim(self, req, ctx):
            resp = pb.Receipt()
            proto_fill(resp, "claim")
            proto_echo(req, resp)
            return resp
        def Renew(self, req, ctx):
            resp = pb.Renewal()
            proto_fill(resp, "renew")
            proto_echo(req, resp)
            return resp

    pg.add_WharfRegistryServicer_to_server(Servicer(), srv)
    port = srv.add_insecure_port("127.0.0.1:0")
    srv.start()
    try:
        chan = _grpc.insecure_channel("127.0.0.1:%d" % port)
        stub = pg.WharfRegistryStub(chan)
        reqm = pb.DockRequest()
        proto_fill(reqm, "dock")
        reqvals = {}
        for fd in reqm.DESCRIPTOR.fields:
            if fd.is_repeated or fd.type in (fd.TYPE_MESSAGE, fd.TYPE_ENUM):
                continue
            v = getattr(reqm, fd.name)
            if v not in (None, "", False, 0, 0.0, b""):
                reqvals[fd.name] = v
        for name in ("Claim", "Renew"):
            try:
                resp = getattr(stub, name)(reqm, timeout=5)
            except Exception as e:
                note("%s roundtrip call failed: %r" % (name, e))
                continue
            rby = {fd.name: fd for fd in resp.DESCRIPTOR.fields}
            shared = bad = 0
            for fn, v in reqvals.items():
                fd = rby.get(fn)
                if fd is None or fd.type != reqm.DESCRIPTOR.fields_by_name[fn].type:
                    continue
                if fd.is_repeated or fd.type in (fd.TYPE_MESSAGE, fd.TYPE_ENUM):
                    continue
                shared += 1
                if getattr(resp, fn) != v:
                    bad += 1
            if shared and bad:
                note("%s roundtrip failed to echo request values (%d/%d fields)" % (name, shared - bad, shared))
            scalars = [fn for fn, fd in rby.items()
                       if not fd.is_repeated and fd.type not in (fd.TYPE_MESSAGE, fd.TYPE_ENUM)]
            if scalars:
                vals = [getattr(resp, fn) for fn in scalars]
                if all(v in (None, "", False, 0, 0.0, b"") for v in vals):
                    note("%s response carried no serialized field values" % name)
    except Exception as e:
        note("grpc roundtrip error: %r" % e)
    finally:
        srv.stop(0)

check_proto()


# ====================================================================== cert
def certcheck(cert, expected, label):
    r = run([sys.executable, "/app/certcheck.py", cert])
    out = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            out[k] = v
    if r.returncode != 0:
        note("%s: certcheck exited %d" % (label, r.returncode)); return False
    if out.get("CN") != expected.get("cn"):
        note("%s: CN=%r want %r" % (label, out.get("CN"), expected.get("cn"))); return False
    if out.get("EXPIRES") != expected.get("expires"):
        note("%s: EXPIRES=%r want %r" % (label, out.get("EXPIRES"), expected.get("expires"))); return False
    if out.get("CHECK_STATUS") != "OK":
        note("%s: CHECK_STATUS=%r" % (label, out.get("CHECK_STATUS"))); return False
    return True


if os.path.exists("/app/cert_expected.json") and os.path.exists("/app/juniper-tls.pem"):
    certcheck("/app/juniper-tls.pem", json.load(open("/app/cert_expected.json")), "visible-cert")


# ====================================================================== S3 download
def mint_expected(acc, sec):
    h = hashlib.sha256((acc + ":" + sec).encode()).hexdigest().upper()
    return {"access_key": "AK-" + h[:10], "secret_key": "SK-" + h[10:22], "role": "operator"}


def check_download(ep, bucket, store_root, out, label):
    os.makedirs(out, exist_ok=True)
    r = run([sys.executable, "/app/download.py", "--endpoint", ep,
             "--bucket", bucket, "--out", out])
    rpath = os.path.join(out, "report.json")
    if not os.path.exists(rpath):
        note("%s: no report (rc=%d %s)" % (label, r.returncode, r.stderr.strip())); return False
    try:
        report = json.load(open(rpath))
    except Exception as e:
        note("%s: report.json unparsable: %r" % (label, e)); return False
    man = json.load(open(os.path.join(store_root, bucket, "manifest.json")))
    cols = man["columns"]
    by = {}
    for f in man["files"]:
        by[f["role"]] = by.get(f["role"], 0) + f["rows"]
        src = os.path.join(store_root, bucket, f["key"])
        want = hashlib.sha256(open(src, "rb").read()).hexdigest()
        dl = os.path.join(out, f["key"])
        if not os.path.isfile(dl):
            note("%s: download.py did not write %s" % (label, f["key"])); return False
        if hashlib.sha256(open(dl, "rb").read()).hexdigest() != want:
            note("%s: downloaded %s byte mismatch" % (label, f["key"])); return False
        df = pd.read_parquet(dl)
        if list(df.columns) != cols or len(df) != f["rows"]:
            note("%s: schema/rows wrong in %s" % (label, f["key"])); return False
    exp_total = sum(by.values())
    if (report.get("downloaded_files") != len(man["files"]) or
            report.get("sha_ok") is not True or
            report.get("total_rows") != exp_total or
            report.get("train_rows") != by.get("train", 0) or
            report.get("val_rows") != by.get("val", 0) or
            report.get("test_rows") != by.get("test", 0) or
            report.get("columns") != cols or
            report.get("splits_complete") is not True):
        note("%s: report facts wrong: %r" % (label, report)); return False
    for role in ("train", "val", "test"):
        if by.get(role, 0):
            merged = os.path.join(out, role + ".parquet")
            if not os.path.isfile(merged):
                note("%s: missing merged %s.parquet" % (label, role)); return False
            elif len(pd.read_parquet(merged)) != by[role]:
                note("%s: merged %s rows wrong" % (label, role)); return False
    return True


# visible download against the live object store served from /app/realm
if os.path.exists("/app/realm/moorings/manifest.json"):
    check_download("http://127.0.0.1:9000", "moorings", "/app/realm", "/tmp/vdl", "visible-download")


# ====================================================================== creds probe
def probe(control, acc, sec):
    r = run([sys.executable, "/app/creds_probe.py", "--control", control,
             "--access-key", acc, "--secret-key", sec])
    try:
        return r, json.load(open("/app/probe_result.json"))
    except Exception:
        return r, None


# visible control head (already running at 9001 in the ready default pair)
r, res = probe("http://127.0.0.1:9001", "wharfmaster", "wharfmaster")
vm = mint_expected("wharfmaster", "wharfmaster")
if not (res and res.get("reachable") is True and res.get("access_key") == vm["access_key"]
        and res.get("secret_key") == vm["secret_key"] and res.get("role") == "operator"):
    note("visible-probe did not recover minted creds: %r" % (res,))


# ====================================================================== hidden scenarios
scenarios = sorted(n for n in os.listdir(HID) if os.path.isdir(os.path.join(HID, n)))
if len(scenarios) < 2:
    note("expected >= 2 hidden scenarios, got %d" % len(scenarios))

obj_ports = [9101, 9102, 9103]
ctl_ports = [9201, 9202, 9203]
procs = []
try:
    for idx, s in enumerate(scenarios):
        sd = os.path.join(HID, s)
        # cert
        cjson = os.path.join(sd, "cert_expected.json")
        if os.path.exists(cjson) and os.path.exists(os.path.join(sd, "endpoint.pem")):
            certcheck(os.path.join(sd, "endpoint.pem"), json.load(open(cjson)), "s/" + s + "-cert")
        # object store
        store = os.path.join(sd, "store")
        if os.path.isdir(store):
            buckets = [b for b in os.listdir(store) if os.path.isdir(os.path.join(store, b))]
            if len(buckets) != 1:
                note("s/%s: expected one bucket in store" % s)
            else:
                bucket = buckets[0]
                port = obj_ports[idx % len(obj_ports)]
                p = subprocess.Popen([sys.executable, "/app/object_server.py", "--root", store,
                                      "--port", str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                procs.append(p)
                if wait_up(port):
                    check_download("http://127.0.0.1:%d" % port, bucket, store, "/tmp/hdl_%s" % s, "s/" + s + "-download")
                else:
                    note("s/%s: hidden object server never came up" % s)
        # control probe
        ce = os.path.join(sd, "creds_expected.json")
        if os.path.exists(ce):
            c = json.load(open(ce))
            cport = ctl_ports[idx % len(ctl_ports)]
            cp = subprocess.Popen([sys.executable, "/app/control_server.py", "--port", str(cport),
                                   "--def-access", c["server_access"], "--def-secret", c["server_secret"]],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            procs.append(cp)
            if wait_up(cport):
                r, res = probe("http://127.0.0.1:%d" % cport, c["probe_access"], c["probe_secret"])
                want = c["expected_reachable"]
                if not res or res.get("reachable") != want:
                    note("s/%s: probe reachable=%r want %r" % (s, res, want))
                elif want:
                    exp = c["expected_minted"]
                    if (res.get("access_key") != exp["access_key"] or
                            res.get("secret_key") != exp["secret_key"] or
                            res.get("role") != c["expected_role"]):
                        note("s/%s: probe minted creds mismatch %r" % (s, res))
                else:
                    if res.get("access_key") is not None or res.get("secret_key") is not None:
                        note("s/%s: sealed probe fabricated creds" % s)
        else:
            note("s/%s: missing creds_expected.json" % s)
finally:
    for p in procs:
        try:
            p.terminate()
        except Exception:
            pass


# ====================================================================== reward
if fail:
    print("FAILURES:")
    for m in fail:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    print("REWARD=0")
else:
    print("ALL PASS")
    open("/logs/verifier/reward.txt", "w").write("1")
    print("REWARD=1")
sys.exit(0)
PY