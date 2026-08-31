#!/usr/bin/env python3
"""Verifier helper for marble-shard.

1. Visible appliance: execute /app/recover.py k7 live; byte-compare to the
   golden payload; also byte-compare the /app/recovered.txt deliverable.
2. Hidden states: spawn several keeper processes holding deleted decoy shards,
   execute /app/recover.py against them, byte-compare the recovered payload to
   the matching shard, and check the negative-query exit-2 contract.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

RECOVER = "/app/recover.py"
failures = []

KEEPER_CODE = (
    "import os,sys,time;f=os.open(sys.argv[1],os.O_RDONLY);"
    "os.unlink(sys.argv[1]);time.sleep(240)"
)


def spawn_keeper(path):
    return subprocess.Popen(["python3", "-c", KEEPER_CODE, path])


def deleted_fd_exists(pid):
    fddir = "/proc/%s/fd" % pid
    if not os.path.isdir(fddir):
        return False
    for fd in os.listdir(fddir):
        try:
            if os.readlink(os.path.join(fddir, fd)).endswith("(deleted)"):
                return True
        except OSError:
            continue
    return False


# ---- 1. visible appliance -------------------------------------------------
if not os.path.isfile(RECOVER):
    failures.append("missing /app/recover.py")
else:
    out = "/tmp/marble_visible_recovered.bin"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([sys.executable, RECOVER, "k7", out],
                       capture_output=True, text=True, timeout=120)
    golden = open("/tests/visible_golden.bin", "rb").read()
    if r.returncode != 0:
        failures.append("visible run exit %d" % r.returncode)
    elif not os.path.isfile(out) or open(out, "rb").read() != golden:
        failures.append("visible run payload mismatch")
    if not os.path.isfile("/app/recovered.txt") or \
            open("/app/recovered.txt", "rb").read() != golden:
        failures.append("/app/recovered.txt missing or not byte-exact")

# ---- 2. hidden appliance states -------------------------------------------
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(d for d in os.listdir(hidden)
                   if os.path.isfile(os.path.join(hidden, d, "case.json")))
    if not cases:
        failures.append("no hidden cases present")
    tmpdir = tempfile.mkdtemp(prefix="marble_hidden_")
    try:
        for c in cases:
            base = os.path.join(hidden, c)
            meta = json.load(open(os.path.join(base, "case.json")))
            procs = []
            try:
                live = 0
                for name in meta["shards"]:
                    src = os.path.join(base, name)
                    dst = os.path.join(tmpdir, "%s_%s" % (c, name))
                    shutil.copyfile(src, dst)
                    p = spawn_keeper(dst)
                    procs.append(p)
                time.sleep(1.0)
                for p in procs:
                    if p.poll() is None and deleted_fd_exists(p.pid):
                        live += 1
                if live == 0:
                    failures.append("hidden '%s': no keeper holds a deleted fd" % c)
                out = os.path.join(tmpdir, "%s_out.bin" % c)
                if os.path.exists(out):
                    os.remove(out)
                r = subprocess.run([sys.executable, RECOVER, meta["query"], out],
                                   capture_output=True, text=True, timeout=120)
                expect = meta["expect"]
                if expect is None:
                    if r.returncode != 2:
                        failures.append("hidden '%s': negative query exit %d (want 2)"
                                        % (c, r.returncode))
                    elif os.path.exists(out):
                        failures.append("hidden '%s': negative query wrote output" % c)
                else:
                    if r.returncode != 0:
                        failures.append("hidden '%s': exit %d (want 0)"
                                        % (c, r.returncode))
                    else:
                        want = open(os.path.join(base, expect), "rb").read()
                        got = open(out, "rb").read() if os.path.isfile(out) else None
                        if got != want:
                            failures.append("hidden '%s': payload mismatch (wrong fd or "
                                            "wrong match)" % c)
            finally:
                for p in procs:
                    try:
                        p.kill()
                    except OSError:
                        pass
                for p in procs:
                    p.wait()
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
