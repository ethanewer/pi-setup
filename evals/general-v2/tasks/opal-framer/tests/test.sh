#!/bin/bash
# Verifier for opal-framer: checks the visible-case deliverables, ENFORCES the
# no-modify rule on /app/image.bin, and EXECUTES the deliverable program
# (/app/framer.py) on the visible case and on every hidden case in
# /tests/hidden (round trips, invalid caps, missing inputs, corrupted frames).
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_IMAGE_SHA="$(sha256sum /app/image.bin 2>/dev/null | awk '{print $1}')"

python3 - "$PRISTINE_IMAGE_SHA" <<'PY'
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys

FRAMER = "/app/framer.py"
IMAGE = "/app/image.bin"
PAYLOAD = "/app/payload"
REASS = "/app/reassembled.bin"
HD = "/tests/hidden"
pristine_sha = sys.argv[1]
probs = []


def check(name, cond, detail=""):
    if not cond:
        probs.append("%s  <%s>" % (name, detail))


def sha(b):
    return hashlib.sha256(b).hexdigest()


check("no_modify_image",
      os.path.isfile(IMAGE) and sha(open(IMAGE, "rb").read()) == pristine_sha,
      "visible input modified or missing")

check("framer_exists", os.path.isfile(FRAMER))

if os.path.isfile(FRAMER) and os.path.isfile(IMAGE) and not probs:
    visible = open(IMAGE, "rb").read()

    # ---- visible deliverable: /app/payload/index.json ----
    idx = os.path.join(PAYLOAD, "index.json")
    if not os.path.isfile(idx):
        probs.append("payload_manifest_missing  </app/payload/index.json>")
    else:
        try:
            m = json.load(open(idx))
            cap = 1000
            n = math.ceil(len(visible) / cap)
            check("payload_frames", m.get("frames") == n, m.get("frames"))
            check("payload_size", m.get("size") == len(visible), m.get("size"))
            check("payload_cap", m.get("cap") == cap, m.get("cap"))
            check("payload_sha", m.get("sha256") == sha(visible))
            parts = m.get("parts")
            check("payload_parts_len", isinstance(parts, list) and len(parts) == n)
            ok_parts = isinstance(parts, list)
            if ok_parts:
                for i, p in enumerate(parts):
                    lo = i * cap
                    want = visible[lo:lo + cap]
                    ok_parts &= (p.get("name") == "frame_%05d.bin" % i
                                 and p.get("offset") == lo
                                 and p.get("length") == len(want)
                                 and p.get("sha256") == sha(want))
                    fp = os.path.join(PAYLOAD, p.get("name", ""))
                    if not os.path.isfile(fp):
                        ok_parts = False
                    else:
                        ok_parts &= sha(open(fp, "rb").read()) == sha(want)
            check("payload_parts_content", ok_parts)
        except Exception as exc:
            probs.append("payload_manifest_unreadable  <%s>" % exc)

    # ---- visible deliverable: /app/reassembled.bin ----
    if os.path.isfile(REASS):
        check("reassembled_bytes",
              open(REASS, "rb").read() == visible)
    else:
        probs.append("reassembled_missing  </app/reassembled.bin>")

    # ---- execute deliverable on the visible case in a fresh dir ----
    work = "/tmp/opal_framer_visible"
    shutil.rmtree(work, ignore_errors=True)
    r = subprocess.run([sys.executable, FRAMER, "pack", IMAGE,
                        os.path.join(work, "pl"), "1000"],
                       capture_output=True, text=True, timeout=120)
    check("visible_pack_exit0", r.returncode == 0, r.stderr[-200:])
    r = subprocess.run([sys.executable, FRAMER, "unpack",
                        os.path.join(work, "pl"),
                        os.path.join(work, "back.bin")],
                       capture_output=True, text=True, timeout=120)
    back = os.path.join(work, "back.bin")
    check("visible_unpack_exit0", r.returncode == 0, r.stderr[-200:])
    check("visible_round_trip", os.path.isfile(back)
          and open(back, "rb").read() == visible)

    # ---- hidden cases ----
    for case in sorted(os.listdir(HD)):
        cdir = os.path.join(HD, case)
        args_p = os.path.join(cdir, "args.json")
        if not os.path.isfile(args_p):
            probs.append("hidden_%s_no_args" % case)
            continue
        cfg = json.load(open(args_p))
        work = "/tmp/opal_framer_%s" % case
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work)
        inp = os.path.join(cdir, cfg.get("input", "input.bin"))
        out_dir = os.path.join(work, "out")
        out_file = os.path.join(work, "back.bin")

        if cfg.get("invalid_cap"):
            r = subprocess.run([sys.executable, FRAMER, "pack", inp,
                                out_dir, str(cfg["cap"])],
                               capture_output=True, text=True, timeout=120)
            check("hidden_%s_badcap_fails" % case, r.returncode != 0)
            check("hidden_%s_badcap_stderr" % case, r.stderr.strip() != "")
            check("hidden_%s_badcap_no_write" % case, not os.path.exists(out_dir))
            continue

        if cfg.get("missing_input"):
            r = subprocess.run([sys.executable, FRAMER, "pack", inp,
                                out_dir, str(cfg["cap"])],
                               capture_output=True, text=True, timeout=120)
            check("hidden_%s_missing_fails" % case, r.returncode != 0)
            check("hidden_%s_missing_stderr" % case, r.stderr.strip() != "")
            check("hidden_%s_missing_no_write" % case, not os.path.exists(out_dir))
            continue

        if not os.path.isfile(inp):
            probs.append("hidden_%s_no_input" % case)
            continue
        raw = open(inp, "rb").read()
        cap = cfg["cap"]
        expect_frames = math.ceil(len(raw) / int(cap))

        r = subprocess.run([sys.executable, FRAMER, "pack", inp, out_dir,
                            str(cap)],
                           capture_output=True, text=True, timeout=120)
        check("hidden_%s_pack_exit0" % case, r.returncode == 0, r.stderr[-200:])
        if r.returncode != 0:
            continue
        try:
            m = json.load(open(os.path.join(out_dir, "index.json")))
            check("hidden_%s_manifest_frames" % case,
                  m.get("frames") == expect_frames
                  and len(m.get("parts", [])) == expect_frames,
                  (m.get("frames"), expect_frames))
            check("hidden_%s_manifest_sha" % case,
                  m.get("sha256") == sha(raw) and m.get("size") == len(raw))
            check("hidden_%s_manifest_cap" % case, m.get("cap") == int(cap))
        except Exception as exc:
            probs.append("hidden_%s_manifest_unreadable  <%s>" % (case, exc))
            continue

        if cfg.get("corrupt"):
            # corrupt the first frame, then unpack must fail without writing
            frames = sorted(f for f in os.listdir(out_dir)
                            if f.startswith("frame_"))
            if not frames:
                probs.append("hidden_%s_no_frames_to_corrupt" % case)
                continue
            fp = os.path.join(out_dir, frames[0])
            b = bytearray(open(fp, "rb").read())
            b[0] ^= 0xFF
            open(fp, "wb").write(bytes(b))
            r = subprocess.run([sys.executable, FRAMER, "unpack", out_dir,
                                out_file],
                               capture_output=True, text=True, timeout=120)
            check("hidden_%s_corrupt_unpack_fails" % case, r.returncode != 0)
            check("hidden_%s_corrupt_msg" % case, "corrupt" in r.stderr.lower(),
                  r.stderr[-200:])
            check("hidden_%s_corrupt_no_output" % case,
                  not os.path.exists(out_file))
            continue

        r = subprocess.run([sys.executable, FRAMER, "unpack", out_dir,
                            out_file],
                           capture_output=True, text=True, timeout=120)
        check("hidden_%s_unpack_exit0" % case, r.returncode == 0,
              r.stderr[-200:])
        check("hidden_%s_round_trip" % case,
              os.path.isfile(out_file) and open(out_file, "rb").read() == raw)

print("verify failures:", probs)
sys.exit(1 if probs else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
