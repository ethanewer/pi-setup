#!/bin/bash
# verifier for tasks/umber-summit (executes-deliverable).
#
# Re-runs the /app outputters and cross-checks every claimed competency:
#   A) detection  - /app/detect.sh + /app/rules.json -> alert.json/report.json,
#                   on the visible logs AND hidden rule/log sets (incl.
#                   empty and malformed edge cases);
#   B) encryption - /app/archive.gpg decrypts to exactly /app/logs, best-mode
#                   names AES256, packet cipher is 9 (AES-256), no plaintext
#                   .tar/.tar.gz remains anywhere;
#   C) cipher-oracle - /app/oracle.py recovers a hidden key within a strict
#                   budget;
#   D) deserialization - /app/worker.py on /app/message.pkl executes the
#                   gadget's command, producing /app/pwn-proof.txt.
# Reward is 1 when every gate passes, else 0.
set -u
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT
exec python3 - <<'PY'
import glob, json, os, re, shutil, subprocess, sys
import atexit

def _safety_reward():
    # Guarantee a reward file exists even if the verifier crashes, so Harbor
    # never sees RewardFileNotFoundError; an unhandled crash scores 0.
    try:
        os.makedirs("/logs/verifier", exist_ok=True)
        if not os.path.exists("/logs/verifier/reward.txt"):
            with open("/logs/verifier/reward.txt", "w") as fh:
                fh.write("0\n")
    except Exception:
        pass

atexit.register(_safety_reward)

fails = []
HALL = "/tests/hidden"

def run(cmd, timeout=None):
    import time
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        r = subprocess.CompletedProcess(cmd, 124)
        r.stdout = (e.stdout or ""); r.stderr = (e.stderr or "")
        r.returncode = 124
        return r

def readj(p):
    with open(p) as fh: return json.load(fh)

# ---------- independent re-implementation of the detection semantics ---------
SRCrc = re.compile(r'\bsrc=([0-9.]+)')

def norm_meta(r, i):
    if not isinstance(r, dict):
        return {"id": "r%d" % i, "pattern": "", "threshold": 0, "severity": "info"}
    pid = r.get("id"); pat = r.get("pattern"); sev = r.get("severity"); th = r.get("threshold")
    try: th = int(th)
    except Exception: th = 0
    return {"id": str(pid) if pid is not None else "r%d" % i,
            "pattern": pat if isinstance(pat, str) else "",
            "threshold": th,
            "severity": sev if isinstance(sev, str) and sev else "info"}

def analyze(rules_path, log_files):
    raw = None
    try:
        with open(rules_path) as fh: raw = json.load(fh)
    except Exception:
        raw = []
    if isinstance(raw, dict): raw = raw.get("rules", [])
    if not isinstance(raw, list): raw = []
    meta = [norm_meta(r, i) for i, r in enumerate(raw)]
    hist = {m["id"]: {"count": 0, "ips": set()} for m in meta}
    events = []
    for lp in log_files:
        if not os.path.isfile(lp): continue
        try:
            fh = open(lp, errors="replace")
        except OSError:
            continue
        for line in fh:
            line = line.rstrip("\n")
            for m in meta:
                if not m["pattern"]: continue
                try: ok = bool(re.compile(m["pattern"]).search(line))
                except re.error: ok = False
                if ok:
                    ms = SRCrc.search(line)
                    src = ms.group(1) if ms else None
                    hist[m["id"]]["count"] += 1
                    if src: hist[m["id"]]["ips"].add(src)
                    events.append((m["id"], src, line))
    return meta, hist, events

def check_detect(rules_path, log_files, tag):
    r = run(["bash", "/app/detect.sh", rules_path] + log_files)
    if r.returncode != 0:
        fails.append("%s: detect rc=%s: %s" % (tag, r.returncode, (r.stderr or "")[-200:]))
        return
    if not (os.path.isfile("/app/alert.json") and os.path.isfile("/app/report.json")):
        fails.append("%s: detect did not write alert.json/report.json" % tag); return
    try:
        al = readj("/app/alert.json"); rp = readj("/app/report.json")
    except Exception as exc:
        fails.append("%s: unparseable output json: %r" % (tag, exc)); return
    meta, hist, events = analyze(rules_path, log_files)
    if not isinstance(al.get("timestamp"), str) or not isinstance(rp.get("timestamp"), str):
        fails.append("%s: missing timestamp string" % tag)
    exp_alerts = []
    exp_stats = {}
    for m in meta:
        s = hist[m["id"]]
        ips = sorted(s["ips"], key=lambda x: (x is None, str(x)))
        exp_stats[m["id"]] = {"id": m["id"], "pattern": m["pattern"],
                              "threshold": m["threshold"], "severity": m["severity"],
                              "matches": s["count"], "unique_ips": len(ips), "ips": ips}
        if s["count"] >= m["threshold"]:
            exp_alerts.append({"id": m["id"], "severity": m["severity"],
                               "matches": s["count"], "ips": ips})
    got_alerts = sorted(al.get("alerts", []), key=lambda x: (x.get("id") or ""))
    exp_alerts = sorted(exp_alerts, key=lambda x: (x.get("id") or ""))
    if got_alerts != exp_alerts:
        fails.append("%s: alert mismatch got=%r exp=%r" % (tag, got_alerts, exp_alerts))
    gstats = rp.get("statistics", {})
    for rid, est in exp_stats.items():
        gs = gstats.get(rid)
        if gs is None:
            fails.append("%s: stats missing rule %s" % (tag, rid)); continue
        for k in ("matches", "unique_ips", "ips", "threshold", "severity"):
            if gs.get(k) != est[k]:
                fails.append("%s: rule %s %s got %r exp %r" % (tag, rid, k, gs.get(k), est[k]))
    gev = [(e.get("rule"), e.get("src"), e.get("line")) for e in rp.get("events", [])]
    if sorted(gev, key=repr) != sorted(events, key=repr):
        fails.append("%s: event multiset mismatch (%d vs %d)" % (tag, len(gev), len(events)))

# --------------------------------------------------------------------------- A
if not os.path.isfile("/app/detect.sh") or not os.access("/app/detect.sh", os.X_OK):
    fails.append("missing/not-executable /app/detect.sh")
if not os.path.isfile("/app/rules.json"):
    fails.append("missing /app/rules.json")

check_detect("/app/rules.json",
             ["/app/logs/access.log", "/app/logs/auth.log"], "visible")
for tag, rules, logs in (
        ("hidden_detect_1",
         os.path.join(HALL, "detect_1", "rules.json"),
         sorted(glob.glob(os.path.join(HALL, "detect_1", "logs", "*")))),
        ("hidden_detect_2_empty",
         os.path.join(HALL, "detect_2", "rules.json"),
         sorted(glob.glob(os.path.join(HALL, "detect_2", "logs", "*")))),
        ("hidden_detect_3_malformed",
         os.path.join(HALL, "detect_3", "rules.json"),
         sorted(glob.glob(os.path.join(HALL, "detect_3", "logs", "*"))))):
    check_detect(rules, logs, tag)

# ---------- B encryption ----------
# execute the encryption deliverable itself: it must rebuild the deterministic
# archive + best-mode.txt from the operator sources; the gates below then audit
# the resulting envelope and the no-plaintext-leftover guarantee.
er = run(["bash", "/app/encrypt.sh"])
if er.returncode != 0:
    fails.append("encrypt.sh rc=%s: %s" % (er.returncode, (er.stderr or "")[-200:]))

if not os.path.isfile("/app/archive.gpg"):
    fails.append("missing /app/archive.gpg")
else:
    try:
        with open("/app/.passw") as fh: PASS = fh.read() # not a user file
    except Exception:
        try:
            with open("/app/.vault-pass") as fh: PASS = fh.read().strip()
        except Exception:
            PASS = "RidgeSaddle-7-private"
    d = run(["gpg", "--batch", "--yes", "--pinentry-mode", "loopback",
             "--passphrase", PASS, "--list-packets", "/app/archive.gpg"])
    packets = d.stdout + d.stderr
    if "cipher 9" not in packets:
        fails.append("archive.gpg not AES-256 (cipher 9 not in packets): %s"
                     % (packets[-300:]))
    dg = run(["gpg", "--batch", "--yes", "--pinentry-mode", "loopback",
              "--passphrase", PASS, "--decrypt", "-o", "/tmp/unpack.tar.gz",
              "/app/archive.gpg"])
    if dg.returncode != 0:
        fails.append("decrypt archive.gpg failed: %s" % ((dg.stderr or "")[-200:]))
    else:
        os.makedirs("/tmp/unpack", exist_ok=True)
        tx = run(["tar", "-tzf", "/tmp/unpack.tar.gz"])
        names = tx.stdout.split()
        reptile = {"logs/access.log", "logs/auth.log"}
        if not reptile.issubset(set(n for n in names if n.endswith("/access.log") or n.endswith("/auth.log"))):
            # normalize any leading './'
            norm = set(n.lstrip("./") for n in names)
            if not norm.issuperset(reptile):
                fails.append("archive entries wrong: %s" % names)
        ex = run(["tar", "-xzf", "/tmp/unpack.tar.gz", "-C", "/tmp/unpack"])
        if ex.returncode != 0:
            fails.append("extract failed: %s" % ((ex.stderr or "")[-120:]))
        else:
            for rel in ("logs/access.log", "logs/auth.log"):
                got = "/tmp/unpack/" + rel
                want = "/app/" + rel
                if not (os.path.isfile(got) and os.path.isfile(want)):
                    fails.append("archive/lenient %s missing" % rel); continue
                if open(got, "rb").read() != open(want, "rb").read():
                    fails.append("decrypted archive %s != original" % rel)
    # no plaintext archive remains under /app (the verifier's own extraction
    # drops files under /tmp, so only /app is audited for agent leftovers)
    leftovers = []
    for root, _, fs in os.walk("/app"):
        for f in fs:
            if f.endswith((".tar", ".tar.gz")) and not f.endswith(".gpg"):
                leftovers.append(os.path.join(root, f))
    if leftovers:
        fails.append("plaintext archive intermediate remains: %s" % leftovers[:5])
    bm = "/app/best-mode.txt"
    if not os.path.isfile(bm):
        fails.append("missing /app/best-mode.txt")
    else:
        v = open(bm).read().strip().upper()
        if "AES256" not in v and "AES-256" not in v:
            fails.append("best-mode.txt does not name AES-256: %r" % v)

# --------------------------------------------------------------------------- C
if not os.path.isfile("/app/oracle.py"):
    fails.append("missing /app/oracle.py")
else:
    try:
        with open(os.path.join(HALL, "oracle_1", "key")) as fh:
            hidden_key = fh.read().strip().lower()
    except Exception:
        hidden_key = None
    if hidden_key:
        with open("/app/.vault-cipher-key", "w") as fh:
            fh.write(hidden_key)
    r = run(["timeout", "25", "python3", "/app/oracle.py"])
    if r.returncode != 0:
        fails.append("oracle.py rc=%s (budget/success): %s"
                     % (r.returncode, (r.stderr or "")[-200:]))
    else:
        try:
            res = readj("/app/oracle-results.json")
        except Exception as exc:
            res = None
            fails.append("oracle-results.json unreadable: %r" % exc)
        if isinstance(res, dict):
            if res.get("ok") is not True:
                fails.append("oracle-results ok != true: %s" % res)
            if hidden_key and str(res.get("key", "")).lower() != hidden_key:
                fails.append("oracle recovered wrong key got=%r want=%r"
                             % (res.get("key"), hidden_key))
            el = res.get("elapsed_ms")
            if not (isinstance(el, (int, float)) and el is not None and float(el) < 25000):
                fails.append("oracle badly-paced %r" % el)

# --------------------------------------------------------------------------- D
# execute the gadget-author deliverable itself: it re-crafts /app/message.pkl
# and pushes it through the real worker (side effect appears), proving the
# crafted payload end to end; the fresh-process gate below then re-verifies it.
g = run(["python3", "/app/gadget.py"])
if g.returncode != 0:
    fails.append("gadget.py rc=%s: %s" % (g.returncode, (g.stderr or "")[-200:]))

msg = "/app/message.pkl"
if not os.path.isfile(msg):
    fails.append("missing /app/message.pkl")
else:
    try:
        os.remove("/app/pwn-proof.txt")
    except FileNotFoundError:
        pass
    w = run(["python3", "/app/worker.py", msg])
    if w.returncode != 0:
        fails.append("worker deserialize rc=%s: %s" % (w.returncode, (w.stderr or "")[-120:]))
    if not os.path.isfile("/app/pwn-proof.txt"):
        fails.append("pwn-proof.txt not created by deserialization")

# --------------------------------------------------------------------------- result
reward = 1 if not fails else 0
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write(str(reward) + "\n")
sys.stderr.write("failures=%d\n%s\n" % (len(fails), "\n".join(fails)))
sys.exit(0)
PY