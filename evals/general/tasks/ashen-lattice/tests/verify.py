#!/usr/bin/env python3
"""ashen-lattice verifier.

Static-checks and executes every /app deliverable:
  - /app/drone.js: no imports, exports a plain `choose(state)` function;
    driven directly on hidden unit states under /tests/hidden.
  - /app/simulate.js: run as a CLI on a hidden batch and compared to the
    stored expected action list.
  - /app/walkthrough.json: compared against the visible fixture expected.
Exits 0 iff every check passes. All parses guarded.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

H = "/tests/hidden"
fails = []
checks = 0


def run(cmd, timeout=60, err_ctx=""):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        fails.append("%s: ERR %r" % (err_ctx, e))
        return None
    if r.returncode != 0:
        fails.append("%s: rc=%d stderr=%s" % (err_ctx, r.returncode,
                                              (r.stderr or "").strip()[:200]))
        return None
    return r.stdout


def guard_json(text, ctx):
    try:
        return json.loads(text)
    except Exception as e:
        fails.append("%s: unparseable JSON %r" % (ctx, e))
        return None


def main():
    global checks

    # ---------- Deliverable 1: /app/drone.js ----------
    drone_path = "/app/drone.js"
    if not os.path.isfile(drone_path):
        fails.append("missing /app/drone.js")
    else:
        with open(drone_path, "r", encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        if "require(" in src:
            fails.append("drone.js uses require() (import ban violated)")
        if re.search(r"(^|[^A-Za-z0-9_.])import(\s|\()", src, re.M):
            fails.append("drone.js uses import (import ban violated)")
        if re.search(r"\bclass\s+[A-Za-z_$]", src):
            fails.append("drone.js declares a class (plain function required)")
        if "module.exports" not in src:
            fails.append("drone.js has no module.exports")
        checks += 1
        out = run(["node", "-e",
                   "const d = require('/app/drone.js');"
                   "console.log(typeof d.choose, d.choose.length);"],
                  err_ctx="drone.js load")
        if out is not None:
            parts = out.strip().split()
            if len(parts) < 2 or parts[0] != "function" or parts[1] != "1":
                fails.append("drone.js must export a plain one-argument "
                             "function `choose` (got %r)" % out.strip())
        # hidden unit states: drive choose() directly
        unit_dirs = [d for d in sorted(glob.glob(os.path.join(H, "*")))
                     if os.path.isfile(os.path.join(d, "state.json"))]
        if len(unit_dirs) < 2:
            fails.append("fewer than 2 hidden unit cases")
        for d in unit_dirs:
            cid = os.path.basename(d)
            checks += 1
            with open(os.path.join(d, "state.json"), encoding="utf-8") as fh:
                state_raw = fh.read()
            with open(os.path.join(d, "expected.txt"), encoding="utf-8") as fh:
                want = fh.read().strip()
            if guard_json(state_raw, "unit %s state" % cid) is None:
                continue
            out = run(["node", "-e",
                       "const {choose} = require('/app/drone.js');"
                       "const fs = require('fs');"
                       "const s = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));"
                       "console.log(choose(s));",
                       os.path.join(d, "state.json")],
                      err_ctx="unit %s" % cid)
            if out is None:
                continue
            got = out.strip()
            if got not in ("north", "east", "south", "west", "hold"):
                fails.append("unit %s: not an allowed action string %r" % (cid, got))
            elif got != want:
                fails.append("unit %s: got %r want %r" % (cid, got, want))

    # ---------- Deliverable 2: /app/simulate.js ----------
    sim_path = "/app/simulate.js"
    if not os.path.isfile(sim_path):
        fails.append("missing /app/simulate.js")
    else:
        batch_dirs = [d for d in sorted(glob.glob(os.path.join(H, "*")))
                      if os.path.isfile(os.path.join(d, "batch.json"))]
        if len(batch_dirs) < 1:
            fails.append("no hidden batch case")
        for d in batch_dirs:
            bid = os.path.basename(d)
            checks += 1
            with open(os.path.join(d, "expected.json"), encoding="utf-8") as fh:
                want = guard_json(fh.read(), "batch %s expected" % bid)
            if want is None:
                continue
            outp = os.path.join(tempfile.gettempdir(), "al_batch_out.json")
            try:
                os.remove(outp)
            except OSError:
                pass
            out = run(["node", sim_path, os.path.join(d, "batch.json"), outp],
                      err_ctx="batch %s" % bid)
            if out is None:
                continue
            if not os.path.isfile(outp):
                fails.append("batch %s: no output file written" % bid)
                continue
            with open(outp, encoding="utf-8") as fh:
                got = guard_json(fh.read(), "batch %s output" % bid)
            if got is None:
                continue
            if got != want:
                fails.append("batch %s: got %r want %r" % (bid, got, want))

    # ---------- Deliverable 3: /app/walkthrough.json ----------
    checks += 1
    walk = "/app/walkthrough.json"
    if not os.path.isfile(walk):
        fails.append("missing /app/walkthrough.json")
    else:
        try:
            with open(walk, encoding="utf-8") as fh:
                got = json.load(fh)
            with open("/tests/expected/walkthrough.json", encoding="utf-8") as fh:
                want = json.load(fh)
            if got != want:
                fails.append("walkthrough.json got %r want %r" % (got, want))
        except Exception as e:
            fails.append("walkthrough comparison failed: %r" % e)

    print("verify checks=%d" % checks)
    print("verify failures:", fails)
    sys.exit(1 if fails else 0)


main()
