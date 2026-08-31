#!/usr/bin/env bash
# wren-link verifier: re-runs the agent's /app/link.sh on hidden module sets,
# checks /app/plugin.bc symbol resolution with llvm-nm, and executes
# /app/skerry_demo. Writes 1/0 to /logs/verifier/reward.txt; never crashes on
# missing/malformed agent output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import os, re, subprocess, sys, tempfile

failures = []
LINK = "/app/link.sh"
PLUGIN = "/app/plugin.bc"
DEMO = "/app/skerry_demo"
EXPECTED_VISIBLE = "gain=12\nmix=21\nshape=34\nlimit=36\n"
WANT_FUNCS = ["sk_gain", "sk_mix", "sk_shape", "sk_limit"]


def sh(cmd, timeout=120):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


# --- 0. deliverables exist ---
for p in (LINK, PLUGIN, DEMO):
    if not os.path.isfile(p):
        failures.append("missing deliverable %s" % p)
if os.path.isfile(LINK) and not os.access(LINK, os.X_OK):
    failures.append("/app/link.sh not executable")

# --- 1. /app/plugin.bc symbol resolution via llvm-nm ---
if os.path.isfile(PLUGIN):
    r = sh(["llvm-nm-18", "--defined-only", PLUGIN])
    defined = set(re.findall(r"\s[TtWw]\s(\w+)", r.stdout)) if r.returncode == 0 else set()
    r2 = sh(["llvm-nm-18", "--undefined-only", PLUGIN])
    undef = set(re.findall(r"\sU\s(\w+)", r2.stdout)) if r2.returncode == 0 else set()
    if r.returncode != 0:
        failures.append("llvm-nm-18 --defined-only failed on plugin.bc")
    if r2.returncode != 0:
        failures.append("llvm-nm-18 --undefined-only failed on plugin.bc")
    for fn in WANT_FUNCS:
        if fn not in defined:
            failures.append("plugin.bc does not define %s" % fn)
        if fn in undef:
            failures.append("plugin.bc still has %s undefined (cross-module "
                            "reference not resolved)" % fn)

# --- 2. visible demo runs ---
if os.path.isfile(DEMO) and os.access(DEMO, os.X_OK):
    try:
        r = sh([DEMO], timeout=30)
        if r.returncode != 0:
            failures.append("skerry_demo exit %d" % r.returncode)
        elif r.stdout.strip() != EXPECTED_VISIBLE.strip():
            failures.append("skerry_demo output %r" % r.stdout)
    except Exception as exc:
        failures.append("skerry_demo crashed: %r" % exc)
else:
    failures.append("skerry_demo missing or not executable")

# --- 3. hidden module sets: re-run link.sh generically ---
for setname, mods in (("set-a", ["core.ll", "trim.ll"]),
                      ("set-b", ["seq1.ll", "seq2.ll", "seq3.ll"])):
    base = "/tests/hidden/%s" % setname
    exp = os.path.join(base, "expected.txt")
    mainsrc = os.path.join(base, "main.c")
    if not (os.path.isfile(exp) and os.path.isfile(mainsrc)):
        failures.append("hidden %s fixtures missing" % setname)
        continue
    if not (os.path.isfile(LINK) and os.access(LINK, os.X_OK)):
        continue  # already reported
    try:
        with tempfile.TemporaryDirectory() as td:
            out_bc = os.path.join(td, "combined.bc")
            mod_paths = [os.path.join(base, m) for m in mods]
            r = sh([LINK, out_bc] + mod_paths, timeout=180)
            if r.returncode != 0 or not os.path.isfile(out_bc):
                failures.append("hidden %s: link.sh failed rc=%d %r"
                                % (setname, r.returncode, r.stderr[:200]))
                continue
            main_bc = os.path.join(td, "main.bc")
            demo = os.path.join(td, "demo")
            r = sh(["clang-18", "-c", "-emit-llvm", mainsrc, "-o", main_bc])
            if r.returncode != 0:
                failures.append("hidden %s: harness compile failed" % setname)
                continue
            r = sh(["clang-18", "-O1", main_bc, out_bc, "-o", demo])
            if r.returncode != 0:
                failures.append("hidden %s: final link failed (undefined or "
                                "duplicate symbols?) rc=%d %r"
                                % (setname, r.returncode, r.stderr[-300:]))
                continue
            r = sh([demo], timeout=30)
            want = open(exp).read()
            if r.returncode != 0:
                failures.append("hidden %s: demo exit %d" % (setname, r.returncode))
            elif r.stdout.strip() != want.strip():
                failures.append("hidden %s: output %r want %r"
                                % (setname, r.stdout, want))
    except Exception as exc:
        failures.append("hidden %s harness error: %r" % (setname, exc))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
