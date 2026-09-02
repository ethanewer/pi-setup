#!/usr/bin/env python3
"""Verifier for echo-latch (executed by tests/test.sh)."""
import os
import shutil
import signal
import subprocess
import sys
import time

TOOL = "/app/reclaim_fd.py"
GOLDEN = "/tests/fd_golden.bin"
fails = []


def run_tool(pidfile, out_path, timeout=60):
    """Run the agent's tool; return True iff it exited 0 and wrote out_path."""
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run([sys.executable, TOOL, pidfile, out_path],
                           capture_output=True, text=True, timeout=timeout)
    except Exception as exc:
        fails.append("tool crashed on %s: %r" % (pidfile, exc))
        return False
    if r.returncode != 0:
        fails.append("tool exit=%d on %s" % (r.returncode, pidfile))
        return False
    return os.path.isfile(out_path)


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


if not os.path.isfile(TOOL):
    fails.append("missing /app/reclaim_fd.py")
else:
    # ---- visible case: deliverable file must match the golden content ----
    if not os.path.isfile("/app/reclaimed_payload.bin"):
        fails.append("missing /app/reclaimed_payload.bin")
    else:
        try:
            if read_bytes("/app/reclaimed_payload.bin") != read_bytes(GOLDEN):
                fails.append("reclaimed_payload.bin content mismatch")
        except Exception as exc:
            fails.append("reclaimed_payload.bin unreadable: %r" % (exc,))

    # ---- visible case: EXECUTE the tool against the live keeper ----
    pidfile = "/app/spool/.latch.pid"
    keeper_up = os.path.isfile(pidfile)
    if keeper_up:
        out = "/tmp/latch_visible_out.bin"
        if run_tool(pidfile, out):
            if read_bytes(out) != read_bytes(GOLDEN):
                fails.append("live-keeper reclaim content mismatch")
        # informational anti-cheat: the spool name must really be gone
        if os.path.exists("/app/spool/frame_buffer.bin"):
            print("INFO visible spool path still exists (keeper not started?)")
    else:
        print("INFO keeper pidfile missing (entrypoint skipped); "
              "content gate on /app/reclaimed_payload.bin stays strict")

    # ---- hidden cases: spawn fresh keepers with different payloads ----
    hidden_dir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d))) \
        if os.path.isdir(hidden_dir) else []
    if not cases:
        fails.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        payload_src = os.path.join(base, "payload.bin")
        expected = os.path.join(base, "expected.bin")
        if not (os.path.isfile(payload_src) and os.path.isfile(expected)):
            fails.append("hidden '%s' malformed" % c)
            continue
        work = "/tmp/latch_case_%s" % c
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work)
        live_payload = os.path.join(work, "spill.bin")
        shutil.copyfile(payload_src, live_payload)
        decoys = []
        for k, name in enumerate(("decoy_a.txt", "decoy_b.log")):
            p = os.path.join(work, name)
            with open(p, "w") as fh:
                fh.write("decoy %d\n" % k)
            decoys.append(p)
        pidfile = os.path.join(work, "run", "keeper.pid")
        proc = subprocess.Popen(
            [sys.executable, "/tests/hidden_keeper.py", pidfile, live_payload]
            + decoys,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        try:
            deadline = time.time() + 10
            while time.time() < deadline and not os.path.isfile(pidfile):
                time.sleep(0.1)
            if not os.path.isfile(pidfile):
                fails.append("hidden '%s': keeper never wrote pidfile" % c)
                continue
            out = os.path.join(work, "out.bin")
            if run_tool(pidfile, out):
                if read_bytes(out) != read_bytes(expected):
                    fails.append("hidden '%s': content mismatch" % c)
                elif os.path.exists(live_payload):
                    fails.append("hidden '%s': payload path still present "
                                 "(wrong fd read?)" % c)
        finally:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

print("verify failures:", fails)
sys.exit(1 if fails else 0)
