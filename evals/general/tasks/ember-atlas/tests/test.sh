#!/bin/bash
# Verifier for ember-atlas: ENFORCES the no-modify rule on the shipped /app
# fixtures, EXECUTES the deliverable (/app/fetch_model.py) — fetch from fresh
# hidden hub servers on free ports, then verify FULLY OFFLINE with every hub
# server shut down — and checks the visible /app/hf_cache deliverable.
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

python3 - <<'PY'
import hashlib, json, os, shutil, signal, socket, subprocess, sys, time
import urllib.request

SOLVE = "/app/fetch_model.py"
SERVER = "/app/hub_server.py"
failures = []


def note(m):
    failures.append(m)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_health(port, tries=50):
    for _ in range(tries):
        try:
            urllib.request.urlopen("http://127.0.0.1:%d/health" % port,
                                   timeout=1)
            return True
        except Exception:
            time.sleep(0.2)
    return False


def kill_all_hubs():
    # kill every hub_server.py process (visible + any leftovers)
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as fh:
                cmd = fh.read().decode(errors="replace")
        except OSError:
            continue
        if "hub_server.py" in cmd:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except OSError:
                pass
    time.sleep(0.7)


def run(args, timeout=180):
    try:
        return subprocess.run(args, capture_output=True, text=True,
                              timeout=timeout)
    except Exception as e:
        class R:
            returncode = -1
            stdout = ""
            stderr = "launch failure: %s" % e
        return R()


def ref_generation(model_dir, repo_id, prompt):
    """Reference greedy generation straight from a local model directory."""
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(model_dir, local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(model_dir,
                                                 local_files_only=True)
    model.eval()
    with torch.no_grad():
        ids = tok(prompt, return_tensors="pt")
        out = model.generate(
            **ids, max_new_tokens=4, do_sample=False, num_beams=1,
            pad_token_id=tok.pad_token_id if tok.pad_token_id is not None
            else tok.eos_token_id)
    cont = out[0][ids["input_ids"].shape[1]:]
    return tok.decode(cont, skip_special_tokens=True)


def parse_verify_json(r):
    if r.returncode != 0:
        return None
    try:
        obj = json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    need = {"repo_id", "prompt", "new_tokens", "generated"}
    if set(obj.keys()) != need:
        return None
    return obj


def snapshot_ok(cache, repo_id):
    """Check the standard cache layout has config + weights + tokenizer."""
    base = os.path.join(cache, "models--%s" % repo_id.replace("/", "--"))
    snap_root = os.path.join(base, "snapshots")
    if not os.path.isdir(snap_root):
        return False
    for rev in os.listdir(snap_root):
        files = set()
        d = os.path.join(snap_root, rev)
        for dirpath, _dirs, fns in os.walk(d):
            for fn in fns:
                files.add(os.path.relpath(os.path.join(dirpath, fn), d))
        if ("config.json" in files
                and any(f.endswith((".safetensors", ".bin")) for f in files)
                and any(f.startswith("tokenizer") for f in files)):
            return True
    return False


if not os.path.isfile(SOLVE):
    note("missing /app/fetch_model.py")
else:
    # ---------------- no-modify: shipped fixtures ----------------
    try:
        with open("/app/hub_pristine.sha256") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                want, rel = line.split(None, 1)
                path = os.path.join("/app/hub/ridge/topoline-24m", rel)
                got = hashlib.sha256(open(path, "rb").read()).hexdigest()
                if got != want:
                    note("no-modify: %s was modified" % path)
    except Exception as e:
        note("no-modify check failed: %s" % e)
    want_srv = ("6a4cd4dead65a125b901a687f18dd6551cd0dad98ecd31c11d1b777afd3bf7c8")
    got_srv = hashlib.sha256(open(SERVER, "rb").read()).hexdigest()
    if got_srv != want_srv:
        note("no-modify: /app/hub_server.py was modified")

    hidden = "/tests/hidden"
    cases = []
    if os.path.isdir(hidden):
        cases = sorted(os.listdir(hidden))
    if not cases:
        note("no hidden cases")

    for case in cases:
        base = os.path.join(hidden, case)
        try:
            with open(os.path.join(base, "expected.json")) as fh:
                hexp = json.load(fh)
        except Exception:
            note("hidden '%s': expected.json unreadable" % case)
            continue
        repo_id = hexp["repo_id"]
        mode = hexp["mode"]

        port = free_port()
        srv = subprocess.Popen(
            [sys.executable, SERVER, "--root", os.path.join(base, "hubroot"),
             "--port", str(port), "--bind", "127.0.0.1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            if not wait_health(port):
                note("hidden '%s': hub never came up" % case)
                continue

            if mode == "fetch_fail":
                r = run([sys.executable, SOLVE, "fetch",
                         "--endpoint", "http://127.0.0.1:%d" % port,
                         "--repo-id", repo_id,
                         "--cache", "/tmp/ea_cache_%s" % case])
                if r.returncode == 0:
                    note("hidden '%s': fetch should have failed" % case)
                continue

            # mode == success: fresh fetch into a pristine cache
            cache = "/tmp/ea_cache_%s" % case
            if os.path.isdir(cache):
                shutil.rmtree(cache)
            r = run([sys.executable, SOLVE, "fetch",
                     "--endpoint", "http://127.0.0.1:%d" % port,
                     "--repo-id", repo_id, "--cache", cache])
            if r.returncode != 0:
                note("hidden '%s': fetch failed (rc=%s)" % (case, r.returncode))
                continue
            try:
                fobj = json.loads(r.stdout.strip().splitlines()[-1])
                if not (isinstance(fobj, dict)
                        and fobj.get("cached") == repo_id
                        and fobj.get("revision")):
                    note("hidden '%s': fetch JSON wrong" % case)
            except Exception:
                note("hidden '%s': fetch stdout unparseable" % case)
            if not snapshot_ok(cache, repo_id):
                note("hidden '%s': cache layout incomplete" % case)
        finally:
            try:
                srv.terminate()
                srv.wait(timeout=5)
            except Exception:
                srv.kill()

    # unknown-repo fetch must fail too (use h_aurora's server layout offline:
    # spin a fresh server, ask for a bogus repo id, stop it)
    base0 = os.path.join(hidden, "h_aurora")
    if os.path.isdir(base0):
        port = free_port()
        srv = subprocess.Popen(
            [sys.executable, SERVER, "--root", os.path.join(base0, "hubroot"),
             "--port", str(port), "--bind", "127.0.0.1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_health(port)
            r = run([sys.executable, SOLVE, "fetch",
                     "--endpoint", "http://127.0.0.1:%d" % port,
                     "--repo-id", "summit/does-not-exist",
                     "--cache", "/tmp/ea_cache_bogus"])
            if r.returncode == 0:
                note("fetch of unknown repo id should fail")
        finally:
            try:
                srv.terminate()
                srv.wait(timeout=5)
            except Exception:
                srv.kill()

    # ---------------- everything offline from here on ----------------
    kill_all_hubs()

    for case in cases:
        base = os.path.join(hidden, case)
        exp_path = os.path.join(base, "expected.json")
        try:
            with open(exp_path) as fh:
                hexp = json.load(fh)
        except Exception:
            continue
        if hexp["mode"] != "success":
            continue
        repo_id, prompt = hexp["repo_id"], hexp["prompt"]
        cache = "/tmp/ea_cache_%s" % case
        r = run([sys.executable, SOLVE, "verify", "--repo-id", repo_id,
                 "--cache", cache, "--prompt", prompt])
        obj = parse_verify_json(r)
        if obj is None:
            note("hidden '%s': verify failed or bad JSON (rc=%s)"
                 % (case, r.returncode))
            continue
        try:
            src = os.path.join(base, "hubroot", *repo_id.split("/"))
            want = ref_generation(src, repo_id, prompt)
        except Exception as e:
            note("verifier bug: reference generation failed: %s" % e)
            continue
        if obj["generated"] != want:
            note("hidden '%s': generated %r != expected %r"
                 % (case, obj["generated"], want))
        if obj["new_tokens"] != 4 or obj["repo_id"] != repo_id \
                or obj["prompt"] != prompt:
            note("hidden '%s': verify JSON fields wrong" % case)

    # negative verifies (offline): bad cache dir, empty prompt
    r = run([sys.executable, SOLVE, "verify", "--repo-id", "summit/aurora-11m",
             "--cache", "/tmp/ea_no_such_cache", "--prompt", "hello"])
    if r.returncode == 0:
        note("verify with nonexistent cache dir should fail")
    r = run([sys.executable, SOLVE, "verify", "--repo-id", "summit/aurora-11m",
             "--cache", "/tmp/ea_cache_h_aurora", "--prompt", ""])
    if r.returncode == 0:
        note("verify with empty prompt should fail")

    # ---------------- visible deliverable ----------------
    if not os.path.isdir("/app/hf_cache"):
        note("missing /app/hf_cache deliverable")
    elif not snapshot_ok("/app/hf_cache", "ridge/topoline-24m"):
        note("visible cache layout incomplete")
    else:
        r = run([sys.executable, SOLVE, "verify", "--repo-id",
                 "ridge/topoline-24m", "--cache", "/app/hf_cache",
                 "--prompt", "the ridgetop sweep"])
        obj = parse_verify_json(r)
        if obj is None:
            note("visible verify failed or bad JSON (rc=%s)" % r.returncode)
        else:
            try:
                want = ref_generation("/app/hub/ridge/topoline-24m",
                                      "ridge/topoline-24m",
                                      "the ridgetop sweep")
            except Exception as e:
                want = None
                note("verifier bug: visible reference generation failed: %s"
                     % e)
            if want is not None and obj["generated"] != want:
                note("visible generated %r != expected %r"
                     % (obj["generated"], want))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
