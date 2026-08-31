#!/usr/bin/env python3
"""Verifier for amber-cistern (executes-deliverable).

Boots FRESH slotd service instances (visible table + every hidden table under
/tests/hidden), then EXECUTES the deliverable /app/probe.py against each and
validates the produced summaries. Independent of the oracle's probe internals:
tokens are recomputed deterministically and every expected value is derived
from the table + manifest fixtures, never copied from the oracle.
"""
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

APP = "/app"
PROBE = os.path.join(APP, "probe.py")
SUMMARY = os.path.join(APP, "summary.json")
REGISTRY = os.path.join(APP, "registry")
SLOTD = os.path.join(REGISTRY, "slotd.py")
HIDDEN = "/tests/hidden"
VISIBLE_TABLE = os.path.join(REGISTRY, "table.json")
VISIBLE_MANIFEST = os.path.join(REGISTRY, "manifest.txt")

# Pristine fixture hashes (the instruction forbids modifying /app/registry).
PRISTINE_TABLE_SHA = "9359f1a53534fa7b2b11e1b880351903ecd7312b52fdff4a0a0d7f9c81b39774"
PRISTINE_MANIFEST_SHA = "ef2cb0049f144c6852eb2c2ad3396e93903137d8e38daa6cbd88c80416d21f19"

PROBE_RE = re.compile(r"^\s*SLOT\s+([A-Z]{1,8}/[0-9]+/[0-9]+)\s*$")

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg, flush=True)


def token_for(key):
    return hashlib.sha256(("slotd-v1:" + key).encode("utf-8")).hexdigest()[:16]


def probe_keys(manifest_path):
    keys, seen = [], set()
    with open(manifest_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            if raw.lstrip().startswith("#"):
                continue
            m = PROBE_RE.match(raw.rstrip("\n"))
            if not m:
                continue
            k = m.group(1)
            if k not in seen:
                seen.add(k)
                keys.append(k)
    return keys


def expected_summary(table_path, manifest_path):
    with open(table_path, "r", encoding="utf-8") as fh:
        table = json.load(fh)
    ok_slots, unknown, tokens = [], [], {}
    total = 0
    heaviest = None
    for k in probe_keys(manifest_path):
        rec = table.get(k)
        if rec is None:
            unknown.append(k)
            continue
        ok_slots.append(k)
        tokens[k] = token_for(k)
        qty = int(rec["qty"])
        total += qty
        cand = {"slot": k, "sku": str(rec["sku"]), "qty": qty, "token": tokens[k]}
        if heaviest is None or cand["qty"] > heaviest["qty"] or (
                cand["qty"] == heaviest["qty"] and k < heaviest["slot"]):
            heaviest = cand
    return {
        "ok_slots": sorted(ok_slots),
        "unknown": sorted(unknown),
        "tokens": {k: tokens[k] for k in sorted(tokens)},
        "total_qty": total,
        "heaviest": heaviest,
    }


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def run_probe(table, manifest, out_path):
    """Boot a fresh slotd on `table` and EXECUTE /app/probe.py on `manifest`."""
    port = free_port()
    proc = subprocess.Popen(
        [sys.executable, SLOTD, table, str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + 10
        ready = False
        while time.time() < deadline and not ready:
            try:
                c = socket.create_connection(("127.0.0.1", port), timeout=1)
                c.sendall(b"PING\n")
                ready = b'"pong"' in c.recv(4096)
                c.close()
            except OSError:
                time.sleep(0.1)
        if not ready:
            return None
        r = subprocess.run(
            [sys.executable, PROBE, "127.0.0.1", str(port), manifest, out_path],
            capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            print("probe rc=%d stderr=%s" % (r.returncode, r.stderr[-400:]))
            return None
        with open(out_path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        print("run_probe exception:", exc)
        return None
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


def norm(obj):
    if not isinstance(obj, dict):
        raise ValueError("summary is not a dict")
    if set(obj.keys()) != {"ok_slots", "unknown", "tokens", "total_qty",
                           "heaviest"}:
        raise ValueError("wrong keys: %r" % sorted(obj.keys()))
    if not isinstance(obj["ok_slots"], list):
        raise ValueError("ok_slots not a list")
    if not isinstance(obj["unknown"], list):
        raise ValueError("unknown not a list")
    if not isinstance(obj["tokens"], dict):
        raise ValueError("tokens not a dict")
    if not isinstance(obj["total_qty"], int) or isinstance(obj["total_qty"], bool):
        raise ValueError("total_qty not an int")
    if sorted(obj["ok_slots"]) != obj["ok_slots"]:
        raise ValueError("ok_slots not sorted")
    if sorted(obj["unknown"]) != obj["unknown"]:
        raise ValueError("unknown not sorted")
    if sorted(obj["tokens"].keys()) != list(obj["tokens"].keys()):
        raise ValueError("tokens keys not sorted")
    if set(obj["tokens"].keys()) != set(obj["ok_slots"]):
        raise ValueError("tokens keys != ok_slots")
    h = obj["heaviest"]
    if h is not None:
        if not isinstance(h, dict) or set(h.keys()) != {"slot", "sku", "qty",
                                                        "token"}:
            raise ValueError("heaviest shape wrong")
        if h["slot"] not in obj["ok_slots"]:
            raise ValueError("heaviest slot not in ok_slots")
        if h["token"] != obj["tokens"][h["slot"]]:
            raise ValueError("heaviest token mismatch")
    return obj


def main():
    if not os.path.isfile(PROBE):
        fail("missing /app/probe.py")
        return 1
    # no-modify guard on the supplied fixtures
    for path, want in ((VISIBLE_TABLE, PRISTINE_TABLE_SHA),
                       (VISIBLE_MANIFEST, PRISTINE_MANIFEST_SHA)):
        if not os.path.isfile(path):
            fail("fixture missing: %s" % path)
            continue
        with open(path, "rb") as fh:
            if hashlib.sha256(fh.read()).hexdigest() != want:
                fail("fixture modified: %s" % path)

    tmpdir = tempfile.mkdtemp(prefix="amber_cistern_verify_")
    try:
        # --- visible case: EXECUTE the probe on the live visible table ---
        out = os.path.join(tmpdir, "visible.json")
        got = run_probe(VISIBLE_TABLE, VISIBLE_MANIFEST, out)
        want = expected_summary(VISIBLE_TABLE, VISIBLE_MANIFEST)
        try:
            if got is None:
                fail("visible case: probe execution failed")
            else:
                if norm(got) != norm(want):
                    fail("visible case summary mismatch")
        except ValueError as exc:
            fail("visible case invalid: %s" % exc)

        # --- visible-case deliverable /app/summary.json ---
        if not os.path.isfile(SUMMARY):
            fail("missing /app/summary.json")
        else:
            try:
                with open(SUMMARY, "r", encoding="utf-8") as fh:
                    got_sum = json.load(fh)
                if norm(got_sum) != norm(want):
                    fail("/app/summary.json does not match the visible table")
            except Exception as exc:
                fail("/app/summary.json unreadable or invalid: %s" % exc)

        # --- hidden cases ---
        if os.path.isdir(HIDDEN):
            cases = sorted(os.listdir(HIDDEN))
            if not cases:
                fail("no hidden cases present")
            for name in cases:
                base = os.path.join(HIDDEN, name)
                table = os.path.join(base, "table.json")
                manifest = os.path.join(base, "manifest.txt")
                if not (os.path.isfile(table) and os.path.isfile(manifest)):
                    fail("hidden case '%s' malformed" % name)
                    continue
                out = os.path.join(tmpdir, name + ".json")
                got = run_probe(table, manifest, out)
                want = expected_summary(table, manifest)
                try:
                    if got is None:
                        fail("hidden case '%s': probe execution failed" % name)
                    elif norm(got) != norm(want):
                        fail("hidden case '%s' summary mismatch" % name)
                except ValueError as exc:
                    fail("hidden case '%s' invalid: %s" % (name, exc))
        else:
            fail("no hidden cases directory")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    if failures:
        print("verify failures:", failures)
        return 1
    print("amber-cistern verify OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
