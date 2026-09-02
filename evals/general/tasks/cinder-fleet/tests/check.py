#!/usr/bin/env python3
"""Verifier for cinder-fleet (executes-deliverable).

Runs /app/extract.py on the shipped workspace and on every hidden dump. It
checks that /app/secret.txt is persisted with the expected normalization
(stripped contents exactly match the expected secret, lowercase, no
surrounding whitespace), that pin.txt is the correct zero-padded PIN, and that
records.json mirrors the dump's TLV record table (parsed independently by the
verifier). /app deliverables must equal a fresh run's outputs byte-for-byte.
Writes the reward to /logs/verifier/reward.txt.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

REWARD_FILE = "/logs/verifier/reward.txt"
TOOL = "/app/extract.py"
fails = []


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    fails.append(msg)


def parse_records(data):
    recs = []
    i = 0
    while i + 2 <= len(data):
        tag, ln = data[i], data[i + 1]
        if i + 2 + ln > len(data):
            break
        recs.append((tag, ln))
        i += 2 + ln
    return recs


def check_secret(path, expected_secret, label):
    """The competency check: stripped contents match the expected string with
    the documented normalization (lowercase, no surrounding whitespace)."""
    if not os.path.isfile(path):
        fail("%s: missing secret.txt" % label)
        return
    try:
        with open(path, encoding="utf-8") as fh:
            content = fh.read()
    except Exception as exc:
        fail("%s: secret.txt unreadable: %s" % (label, exc))
        return
    body = content[:-1] if content.endswith("\n") else content
    if body != body.strip():
        fail("%s: secret.txt has unexpected surrounding whitespace: %r" % (label, content))
    if body != body.lower():
        fail("%s: secret.txt is not fully lowercase: %r" % (label, body))
    want = expected_secret.strip().lower()
    if body.strip() != want:
        fail("%s: secret %r != expected %r" % (label, body.strip(), want))


def check_records(path, dump_path, expected, label):
    try:
        with open(dump_path, "rb") as fh:
            truth = parse_records(fh.read())
    except Exception as exc:
        fail("%s: verifier could not parse dump.bin: %s" % (label, exc))
        return
    truth_list = [{"tag": "%02x" % t, "length": ln} for t, ln in truth]
    if not os.path.isfile(path):
        fail("%s: missing records.json" % label)
        return
    try:
        with open(path, encoding="utf-8") as fh:
            rec = json.load(fh)
    except Exception as exc:
        fail("%s: records.json unreadable: %s" % (label, exc))
        return
    if not isinstance(rec, dict):
        fail("%s: records.json is not a JSON object" % label)
        return
    got = rec.get("records")
    if not isinstance(got, list) or got != truth_list:
        fail("%s: records table mismatch: %r != %r" % (label, got, truth_list))
    pin = rec.get("pin")
    if pin != expected.get("pin"):
        fail("%s: records.json pin %r != %r" % (label, pin, expected.get("pin")))
    sec = rec.get("secret")
    if not isinstance(sec, str) or sec.strip().lower() != expected["secret"].strip().lower():
        fail("%s: records.json secret %r mismatch" % (label, sec))


def run_case(ws_dir, out_dir, expected, label):
    shutil.rmtree(out_dir, ignore_errors=True)
    try:
        r = subprocess.run([sys.executable, TOOL, ws_dir, out_dir],
                           capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        fail("%s: extract.py timed out" % label)
        return
    if r.returncode != 0:
        fail("%s: extract.py rc=%d stderr=%s" % (label, r.returncode, r.stderr[-300:]))
        return
    check_secret(os.path.join(out_dir, "secret.txt"), expected["secret"], label)
    pin_path = os.path.join(out_dir, "pin.txt")
    if not os.path.isfile(pin_path):
        fail("%s: missing pin.txt" % label)
    else:
        with open(pin_path) as fh:
            pin_body = fh.read()
        pin_body = pin_body[:-1] if pin_body.endswith("\n") else pin_body
        if pin_body != expected["pin"]:
            fail("%s: pin %r != %r" % (label, pin_body, expected["pin"]))
    check_records(os.path.join(out_dir, "records.json"),
                  os.path.join(ws_dir, "dump.bin"), expected, label)


def main():
    if not os.path.isfile(TOOL):
        fail("missing /app/extract.py")
    else:
        # visible run on the shipped workspace
        tmp = tempfile.mkdtemp(prefix="cinder_fleet_vis_")
        run_case("/app/workspace", tmp, {"pin": "8314", "secret": "gravity-owl-42"}, "visible")
        try:
            with open("/tests/expected.json") as fh:
                exp = json.load(fh)
        except Exception as exc:
            fail("tests/expected.json unreadable: %s" % exc)
            exp = {"pin": "8314", "secret": "gravity-owl-42"}

        # top-level deliverables must exist, be normalized, and equal a fresh
        # run byte-for-byte
        for name, out_name in (("secret.txt", "secret.txt"),
                               ("pin.txt", "pin.txt"),
                               ("records.json", "records.json")):
            apath = os.path.join("/app", name)
            if not os.path.isfile(apath):
                fail("deliverable missing: /app/" + name)
                continue
            if not os.path.isfile(os.path.join(tmp, out_name)):
                continue
            with open(apath, "rb") as fh:
                a = fh.read()
            with open(os.path.join(tmp, out_name), "rb") as fh:
                b = fh.read()
            if a != b:
                fail("deliverable /app/%s differs from a fresh run" % name)
        check_secret("/app/secret.txt", exp["secret"], "deliverables")

        # hidden dumps
        hidden_dir = "/tests/hidden"
        if not os.path.isdir(hidden_dir):
            fail("no hidden cases present")
        else:
            for case in sorted(os.listdir(hidden_dir)):
                base = os.path.join(hidden_dir, case)
                exp_path = os.path.join(base, "expected.json")
                try:
                    with open(exp_path) as fh:
                        hexp = json.load(fh)
                except Exception as exc:
                    fail("hidden '%s': expected.json unreadable: %s" % (case, exc))
                    continue
                run_case(base, os.path.join(tempfile.gettempdir(), "cf_" + case), hexp,
                         "hidden/" + case)

    print("verify failures: %d" % len(fails), file=sys.stderr)
    reward = 1 if not fails else 0
    with open(REWARD_FILE, "w") as fh:
        fh.write(str(reward))
    sys.exit(0 if reward else 1)


if __name__ == "__main__":
    main()
