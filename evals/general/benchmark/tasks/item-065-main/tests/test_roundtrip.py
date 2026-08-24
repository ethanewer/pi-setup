#!/usr/bin/env python3
"""item-065-main verifier logic.

Rebuilds the expected corpus tree with make_tree.py, runs the agent's
c4shards.py CLI both ways, and compares byte-for-byte.  Prints reward to
stdout as a float and exits 0.
"""
import os
import shutil
import subprocess
import sys

EXPECTED = "/tmp/expected_tree"
FRESH_BUNDLE = "/tmp/fresh_bundle"
FRESH_RESTORED = "/tmp/fresh_restored"
SHIP_BUNDLE = "/app/bundle_shards"
SHIP_RESTORED = "/tmp/ship_restored"

PY = sys.executable


def cmp_trees(a, b):
    def nodes(root):
        out = set()
        for base, dirs, files in os.walk(root):
            rel = os.path.relpath(base, root)
            for d in dirs:
                out.add("d/" + (os.path.join(rel, d) if rel != "." else d).replace(os.sep, "/"))
            for f in files:
                out.add("f/" + (os.path.join(rel, f) if rel != "." else f).replace(os.sep, "/"))
        return out

    if nodes(a) != nodes(b):
        return False
    pairs = []
    for base, dirs, files in os.walk(a):
        rel = os.path.relpath(base, a)
        for f in files:
            rr = os.path.join(rel, f) if rel != "." else f
            pairs.append((rr, os.path.join(a, rr), os.path.join(b, rr)))
    for rr, pa, pb in pairs:
        if not os.path.exists(pb):
            return False
        if open(pa, "rb").read() != open(pb, "rb").read():
            return False
    return True


def main():
    for p in (EXPECTED, FRESH_BUNDLE, FRESH_RESTORED, SHIP_RESTORED):
        if os.path.exists(p):
            shutil.rmtree(p)

    # 1. expected corpus
    subprocess.run([PY, "/app/make_tree.py", EXPECTED], check=True)

    checks = []
    c4 = "/app/c4shards.py"
    checks.append(os.path.isfile(c4))
    if os.path.isfile(c4):
        src = open(c4, encoding="utf-8").read()
        checks.append("NotImplementedError" not in src)

    # 2. agent's own fresh pack/unpack round trip (small limit to force shards)
    fresh_ok = False
    try:
        subprocess.run([PY, c4, "pack", EXPECTED, FRESH_BUNDLE, "--limit", "256"],
                       check=True, capture_output=True, timeout=120)
        subprocess.run([PY, c4, "unpack", FRESH_BUNDLE, FRESH_RESTORED],
                       check=True, capture_output=True, timeout=120)
        fresh_ok = cmp_trees(EXPECTED, FRESH_RESTORED)
    except Exception:
        fresh_ok = False
    checks.append(fresh_ok)

    # 3. agent's shipped bundle must unpack to the expected tree
    ship_ok = False
    if os.path.isdir(SHIP_BUNDLE) and os.path.isfile(os.path.join(SHIP_BUNDLE, "meta.json")):
        try:
            subprocess.run([PY, c4, "unpack", SHIP_BUNDLE, SHIP_RESTORED],
                           check=True, capture_output=True, timeout=120)
            ship_ok = cmp_trees(EXPECTED, SHIP_RESTORED)
        except Exception:
            ship_ok = False
    checks.append(ship_ok)

    # 4. sharded gzip-ness of the shipped bundle
    shards = []
    if os.path.isdir(SHIP_BUNDLE):
        for name in os.listdir(SHIP_BUNDLE):
            if name.startswith("shard-") and name.endswith(".jsonl.gz"):
                pth = os.path.join(SHIP_BUNDLE, name)
                with open(pth, "rb") as f:
                    magic = f.read(2)
                if magic == b"\x1f\x8b":
                    shards.append(name)
    checks.append(len(shards) >= 2)

    n_true = sum(1 for x in checks if x)
    if all(checks):
        reward = 1.0
    elif fresh_ok and ship_ok:
        reward = 0.9
    elif fresh_ok or ship_ok:
        reward = 0.5
    else:
        reward = 0.0
    print([f"checks passed: {n_true}/{len(checks)}", f"fresh_ok={fresh_ok}",
           f"ship_ok={ship_ok}", f"shards={len(shards)}"])
    print(f"REWARD={reward}")
    return 0


if __name__ == "__main__":
    sys.exit(main())