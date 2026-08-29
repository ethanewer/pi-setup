#!/usr/bin/env python3
"""Driver/verifier for elm-summit.

Independently of the agent's implementation style, checks:
1. a background mlflow tracking server is live at 127.0.0.1:8080/health;
2. the live launch-mode gRPC gateway on the visible config.port round-trips
   Put/Get and Status reports a healthy online cluster with the exact cluster
   name, node roster, and capacity declared by the config;
3. /app/serve.py generalises to fresh hidden configs on fresh ports/stores,
   including a restart/persistence case.

Exit 0 => all checks passed; nonzero => something failed.
The server's own responses are the expected answers (round-trip) plus the
hidden config's declared topology; no hidden values are leaked to the agent.
"""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

import grpc

sys.path.insert(0, "/app")
import atlas_pb2 as pb
import atlas_pb2_grpc as pbg

CONFIG = "/app/config.json"
MLFLOW_PORT = int(os.environ.get("ATLAS_MLFLOW_PORT", "8080"))
FAILS = []


def fail(msg):
    FAILS.append(msg)
    print("  FAIL: " + msg)


def http_healthy(host, port):
    for _ in range(60):
        try:
            with urllib.request.urlopen(
                "http://%s:%d/health" % (host, port), timeout=2
            ) as r:
                if r.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(1)
    return False


def port_open(host, port, timeout=40):
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            sock = socket.create_connection((host, port), timeout=1)
            sock.close()
            return True
        except OSError:
            time.sleep(0.5)
    return False


def grpc_ready(stub, tries=40):
    for _ in range(tries):
        try:
            stub.Status(pb.StatusReq(probe_id="warm"), timeout=5)
            return True
        except Exception:
            time.sleep(0.4)
    return False


def roundtrip(stub, keys):
    for k, v in keys:
        stub.Put(pb.PutReq(key=k, value=v), timeout=5)
        got = stub.Get(pb.GetReq(key=k), timeout=5)
        if got.value != v:
            fail("get mismatch for %r (got %r want %r)" % (k, got.value, v))
            return False
    return True


def check_status(stub, cfg, probe, min_objects=None):
    try:
        s = stub.Status(pb.StatusReq(probe_id=probe), timeout=5)
    except Exception as e:
        fail("%s: Status RPC failed: %r" % (probe, e))
        return False
    ok = True
    if not s.healthy:
        fail("%s: cluster not healthy" % probe)
        ok = False
    if s.cluster != cfg["cluster"]:
        fail("%s: cluster name %r != %r" % (probe, s.cluster, cfg["cluster"]))
        ok = False
    if sorted(s.nodes) != sorted(cfg["nodes"]):
        fail("%s: node roster mismatch" % probe)
        ok = False
    if s.capacity_bytes != int(cfg["capacity_bytes"]):
        fail("%s: capacity_bytes %r != %r" % (probe, s.capacity_bytes, cfg["capacity_bytes"]))
        ok = False
    if min_objects is not None and s.objects < min_objects:
        fail("%s: objects %d < %d" % (probe, s.objects, min_objects))
        ok = False
    if "online" not in s.detail:
        fail("%s: status detail does not report online" % probe)
        ok = False
    if probe and probe not in s.detail:
        fail("%s: status detail does not echo the probe id" % probe)
        ok = False
    return ok


LABEL_LOG = os.environ.get("ATLAS_CHILD_LOG", "/logs/verifier")


def launch_server(config_path, port):
    env = dict(os.environ)
    env["ATLAS_CONFIG"] = config_path
    case_name = os.path.basename(os.path.dirname(config_path))  # "1", "2", "3"
    os.makedirs(LABEL_LOG, exist_ok=True)
    base = os.path.join(LABEL_LOG, "child_%s.log" % case_name)
    target = open(base, "w")
    err = target
    return subprocess.Popen(
        [sys.executable, "/app/serve.py", str(port)],
        env=env,
        stdout=target,
        stderr=err,
    )


def maybe_stop(proc):
    if proc is None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()


def main():
    # ---- 1) mlflow tracking server must be live (started by the agent) ----
    print("checking mlflow at 127.0.0.1:%d/health" % MLFLOW_PORT)
    if http_healthy("127.0.0.1", MLFLOW_PORT):
        print("  mlflow ok")
    else:
        fail("mlflow tracking server not reachable at 127.0.0.1:%d/health" % MLFLOW_PORT)

    # ---- 2) live launch-mode gateway on the visible config.port ----
    cfg = json.load(open(CONFIG))
    vis_port = int(cfg["port"])
    print("checking visible live gateway on port %d" % vis_port)
    vis_ok = False
    if not port_open("127.0.0.1", vis_port):
        fail("launch gateway not listening on port %d" % vis_port)
    else:
        ch = None
        try:
            ch = grpc.insecure_channel("127.0.0.1:%d" % vis_port)
            stub = pbg.AtlasGatewayStub(ch)
            if not grpc_ready(stub):
                fail("visible launch gateway not ready on port %d" % vis_port)
            else:
                keys = [("asset-001", "ridge-font-blue"),
                        ("probe-id", "42"),
                        ("region-pool", "us-east-7")]
                vis_ok = roundtrip(stub, keys) and check_status(
                    stub, cfg, "visible", min_objects=len(keys))
        finally:
            try:
                if ch is not None:
                    ch.close()
            except Exception:
                pass
    if not vis_ok:
        fail("visible launch-mode gateway checks failed")

    # ---- 3) hidden cases: fresh configs / ports / stores ----
    for i in ("1", "2", "3"):
        case_dir = os.path.join("/tests/hidden", i)
        config_path = os.path.join(case_dir, "config.json")
        keys_path = os.path.join(case_dir, "keys.json")
        if not (os.path.exists(config_path) and os.path.exists(keys_path)):
            fail("hidden case %s missing inputs" % i)
            continue
        hcfg = json.load(open(config_path))
        keys = [tuple(x) for x in json.load(open(keys_path))]
        port = int(hcfg["port"])
        print("checking hidden case %s on port %d" % (i, port))

        proc = launch_server(config_path, port)
        ok = False
        try:
            ch = grpc.insecure_channel("127.0.0.1:%d" % port)
            stub = pbg.AtlasGatewayStub(ch)
            if not grpc_ready(stub):
                fail("case%s: gateway never ready on port %d" % (i, port))
            else:
                ok = roundtrip(stub, keys) and check_status(
                    stub, hcfg, "case%s" % i, min_objects=len(keys))
            ch.close()
        except Exception as e:
            fail("case%s: %r" % (i, e))
            ok = False
        finally:
            maybe_stop(proc)

        if hcfg.get("restart", False) and ok:
            # persistence across a restart of the same deliverable on a new port
            port2 = int(hcfg.get("port2", port + 1000))
            proc2 = launch_server(config_path, port2)
            try:
                ch2 = grpc.insecure_channel("127.0.0.1:%d" % port2)
                stub2 = pbg.AtlasGatewayStub(ch2)
                if not grpc_ready(stub2):
                    fail("case%s restart: gateway not ready on new port" % i)
                    ok = False
                else:
                    ok2 = True
                    for k, v in keys:
                        got = stub2.Get(pb.GetReq(key=k), timeout=5)
                        if got.value != v:
                            fail("case%s restart: lost key %r" % (i, k))
                            ok2 = False
                    ok2 = check_status(stub2, hcfg, "case%s-restart" % i,
                                       min_objects=len(keys)) and ok2
                    ok = ok and ok2
                    ch2.close()
            except Exception as e:
                fail("case%s restart error: %r" % (i, e))
                ok = False
            finally:
                maybe_stop(proc2)

        if not ok:
            fail("hidden case %s failed" % i)

    result = not FAILS
    print("RESULT: %s" % ("PASS" if result else "FAIL"))
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()