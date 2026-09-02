#!/bin/bash
# Verifier for drift-quarry: ENFORCES the no-modify rule on the shipped /app
# fixtures, EXECUTES the deliverable (/app/fetch_dataset.py) against the live
# visible store and against fresh hidden object stores (launched on free
# loopback ports), and checks reports/parquet outputs against expected values.
# Writes REWARD (0/1) to /logs/verifier/reward.txt; never crashes on malformed
# agent output.
set -u
mkdir -p /logs/verifier
reward=0
_cleanup() {
    if [ ! -s /logs/verifier/reward.txt ]; then
        echo 0 > /logs/verifier/reward.txt
    fi
}
trap _cleanup EXIT

no_modify_broken=0
check_sha() {
    local path="$1" want="$2"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        return
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        no_modify_broken=1
    fi
}
check_sha /app/realm/cirque/manifest.json \
    5cf0371668e7ab126b6abfed49b5d68f29f524c56f0cb32acbcc5abbcf440131
check_sha /app/object_server.py \
    75db564663805ce8d51760f8a1f1c2d374cbb98882a3845b025694821dbcc4a9

python3 - "$no_modify_broken" <<'PY'
import hashlib, json, os, shutil, socket, subprocess, sys, time
import urllib.request
import pandas as pd

SOLVE = "/app/fetch_dataset.py"
SERVER = "/app/object_server.py"
no_modify_broken = int(sys.argv[1])

failures = []
if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_health(port, tries=50):
    for _ in range(tries):
        try:
            urllib.request.urlopen(
                "http://127.0.0.1:%d/health" % port, timeout=1)
            return True
        except Exception:
            time.sleep(0.2)
    return False


def norm_report(path):
    with open(path) as fh:
        obj = json.load(fh)
    assert isinstance(obj, dict), obj
    need = {"dataset", "version", "columns", "files_downloaded",
            "total_rows", "rows", "splits_complete", "sha_ok", "schema_ok",
            "error"}
    assert set(obj.keys()) == need, sorted(obj.keys())
    return obj


def run_fetch(endpoint, bucket, out_dir, timeout=120):
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--endpoint", endpoint,
             "--bucket", bucket, "--out", out_dir],
            capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None, ""
    return r.returncode, (r.stdout or "")


def check_success(out_dir, expected_report, tag):
    rep_path = os.path.join(out_dir, "report.json")
    if not os.path.isfile(rep_path):
        failures.append("%s: report.json missing" % tag)
        return
    try:
        got = norm_report(rep_path)
    except Exception as e:
        failures.append("%s: report unreadable/bad (%s)" % (tag, e))
        return
    if got != expected_report:
        failures.append("%s: report mismatch" % tag)
        return
    for role, n in expected_report["rows"].items():
        pq = os.path.join(out_dir, "%s.parquet" % role)
        if not expected_report["splits_complete"][role]:
            continue
        if not os.path.isfile(pq):
            failures.append("%s: %s missing" % (tag, pq))
            continue
        try:
            df = pd.read_parquet(pq)
            if list(df.columns) != expected_report["columns"]:
                failures.append("%s: %s columns wrong" % (tag, pq))
            elif len(df) != n:
                failures.append("%s: %s rows %d != %d" % (tag, pq, len(df), n))
        except Exception as e:
            failures.append("%s: %s unreadable (%s)" % (tag, pq, e))


if not os.path.isfile(SOLVE):
    failures.append("missing /app/fetch_dataset.py")
else:
    # ---- visible case (live store on 9000) ----
    rc, out = run_fetch("http://127.0.0.1:9000", "cirque", "/tmp/dq_vis_out")
    exp = None
    try:
        with open("/tests/expected/visible.json") as fh:
            exp = json.load(fh)
    except Exception:
        failures.append("verifier bug: visible expected unreadable")
    if exp is not None:
        if rc != 0 or "FETCH_OK" not in out:
            failures.append("visible case failed (rc=%s)" % rc)
        else:
            check_success("/tmp/dq_vis_out", exp, "visible")

    # visible deliverable: /app/dataset must exist and match
    if os.path.isfile("/app/dataset/report.json"):
        try:
            if norm_report("/app/dataset/report.json") != exp:
                failures.append("/app/dataset/report.json mismatch")
        except Exception:
            failures.append("/app/dataset/report.json unreadable")
    else:
        failures.append("missing /app/dataset/report.json deliverable")

    # ---- hidden cases ----
    hidden = "/tests/hidden"
    if not os.path.isdir(hidden):
        failures.append("no hidden cases")
    else:
        for case in sorted(os.listdir(hidden)):
            base = os.path.join(hidden, case)
            exp_path = os.path.join(base, "expected.json")
            store = os.path.join(base, "store")
            if not (os.path.isfile(exp_path) and os.path.isdir(store)):
                failures.append("hidden '%s' malformed" % case)
                continue
            try:
                with open(exp_path) as fh:
                    hexp = json.load(fh)
            except Exception:
                failures.append("hidden '%s' expected unreadable" % case)
                continue
            bucket = hexp["bucket"]
            work = "/tmp/dq_store_%s" % case
            if os.path.isdir(work):
                shutil.rmtree(work)
            shutil.copytree(store, work)
            port = free_port()
            srv = subprocess.Popen(
                [sys.executable, SERVER, "--root", work,
                 "--port", str(port), "--bind", "127.0.0.1"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                if not wait_health(port):
                    failures.append("hidden '%s': server never came up" % case)
                    continue
                out_dir = "/tmp/dq_out_%s" % case
                rc, out = run_fetch("http://127.0.0.1:%d" % port, bucket,
                                    out_dir)
                if hexp["mode"] == "success":
                    if rc != 0 or "FETCH_OK" not in out:
                        failures.append("hidden '%s' failed (rc=%s)"
                                        % (case, rc))
                    else:
                        check_success(out_dir, hexp["report"],
                                      "hidden/%s" % case)
                else:
                    if rc == 0:
                        failures.append(
                            "hidden '%s' should have failed" % case)
                        continue
                    rep_path = os.path.join(out_dir, "report.json")
                    if not os.path.isfile(rep_path):
                        failures.append(
                            "hidden '%s': no failure report" % case)
                        continue
                    try:
                        rep = norm_report(rep_path)
                    except Exception:
                        failures.append(
                            "hidden '%s': failure report unreadable" % case)
                        continue
                    if hexp.get("sha_ok") is not None and \
                            rep["sha_ok"] != hexp["sha_ok"]:
                        failures.append("hidden '%s': sha_ok wrong" % case)
                    if hexp.get("schema_ok") is not None and \
                            rep["schema_ok"] != hexp["schema_ok"]:
                        failures.append("hidden '%s': schema_ok wrong" % case)
                    if hexp.get("error_contains") and \
                            hexp["error_contains"] not in (rep["error"] or ""):
                        failures.append(
                            "hidden '%s': error token wrong (%s)"
                            % (case, rep["error"]))
            finally:
                srv.terminate()
                try:
                    srv.wait(timeout=5)
                except Exception:
                    srv.kill()

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
