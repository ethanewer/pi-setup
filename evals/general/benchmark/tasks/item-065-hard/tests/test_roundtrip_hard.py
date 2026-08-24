#!/usr/bin/env python3
"""item-065-hard verifier logic."""
import glob
import os
import shutil
import subprocess
import sys

PY = sys.executable
EXPECTED = "/tmp/expected_tree"
C4 = "/app/c4shards.py"
SHIP = "/app/bundle_shards"


def nodes(root):
    out = set()
    for base, dirs, files in os.walk(root):
        rel = os.path.relpath(base, root)
        for d in dirs:
            out.add("d/" + (os.path.join(rel, d) if rel != "." else d).replace(os.sep, "/"))
        for f in files:
            out.add("f/" + (os.path.join(rel, f) if rel != "." else f).replace(os.sep, "/"))
    return out


def equal_trees(a, b):
    if nodes(a) != nodes(b):
        return False
    for base, dirs, files in os.walk(a):
        rel = os.path.relpath(base, a)
        for f in files:
            rr = os.path.join(rel, f) if rel != "." else f
            if open(os.path.join(a, rr), "rb").read() != open(os.path.join(b, rr), "rb").read():
                return False
    return True


def shard_bytes(bundle):
    out = {}
    for fn in sorted(os.listdir(bundle)):
        if fn.startswith("shard-") and fn.endswith(".jsonl.gz"):
            out[fn] = open(os.path.join(bundle, fn), "rb").read()
    return out


def run(args):
    subprocess.run([PY, C4] + args, check=True, capture_output=True, timeout=300)


def main():
    clean = ["/tmp/expected_tree", "/tmp/hb", "/tmp/hr", "/tmp/hx", "/tmp/hxr",
             "/tmp/hb2", "/tmp/det_a", "/tmp/det_b"]
    for p in clean:
        if os.path.exists(p):
            shutil.rmtree(p)

    subprocess.run([PY, "/app/make_tree2.py", EXPECTED], check=True, capture_output=True, timeout=300)
    checks = []

    checks.append(os.path.isfile(C4))
    impl_ok = False
    if os.path.isfile(C4):
        src = open(C4, encoding="utf-8").read()
        impl_ok = "NotImplementedError" not in src
    checks.append(impl_ok)

    # (a) fresh pack/unpack round trip incl. empty dirs + binary
    a_ok = False
    try:
        run(["pack", EXPECTED, "/tmp/hb", "--limit", "128"])
        run(["unpack", "/tmp/hb", "/tmp/hr"])
        a_ok = equal_trees(EXPECTED, "/tmp/hr")
    except Exception:
        a_ok = False
    checks.append(a_ok)

    # (b) exclusion: '*.bin' files absent afterwards (dirs still present)
    b_ok = False
    try:
        run(["pack", EXPECTED, "/tmp/hx", "--limit", "128", "--exclude", "*.bin"])
        run(["unpack", "/tmp/hx", "/tmp/hxr"])
        exp = nodes(EXPECTED)
        got = nodes("/tmp/hxr")
        wanted = {n for n in exp if not (n.startswith("f/blobs/") and n.endswith(".bin"))}
        b_ok = (got == wanted) and equal_trees_ignoring(EXPECTED, "/tmp/hxr",
                                                        excluded=("f/blobs/blob-a.bin", "f/blobs/sub/blob-b.bin"))
    except Exception:
        b_ok = False
    checks.append(b_ok)

    # (c) shipped bundle: >=4 gzip shards and unpacks to the full expected tree
    c_ok = False
    shards = 0
    if os.path.isdir(SHIP):
        shards = 0
        for fn in os.listdir(SHIP):
            if fn.startswith("shard-") and fn.endswith(".jsonl.gz"):
                with open(os.path.join(SHIP, fn), "rb") as f:
                    if f.read(2) == b"\x1f\x8b":
                        shards += 1
        try:
            run(["unpack", SHIP, "/tmp/hr2"])
            c_ok = shards >= 4 and equal_trees(EXPECTED, "/tmp/hr2")
        except Exception:
            c_ok = False
    checks.append(c_ok)

    # (d) determinism: two packs of the same tree produce identical shard bytes
    d_ok = False
    try:
        run(["pack", EXPECTED, "/tmp/det_a", "--limit", "128"])
        run(["pack", EXPECTED, "/tmp/det_b", "--limit", "128"])
        sa, sb = shard_bytes("/tmp/det_a"), shard_bytes("/tmp/det_b")
        d_ok = (list(sa) == list(sb)) and all(sa[k] == sb[k] for k in sa)
    except Exception:
        d_ok = False
    checks.append(d_ok)

    n = sum(1 for x in checks if x)
    if all(checks):
        reward = 1.0
    elif a_ok and c_ok:
        reward = 0.5
    elif a_ok or c_ok:
        reward = 0.25
    else:
        reward = 0.0
    print(f"checks {n}/{len(checks)} a={a_ok} b={b_ok} c={c_ok} d={d_ok} shards={shards}")
    print(f"REWARD={reward}")
    return 0


def equal_trees_ignoring(a, b, excluded):
    e = nodes(a)
    g = nodes(b)
    if g != {x for x in e if x not in set(excluded)}:
        return False
    for base, dirs, files in os.walk(a):
        rel = os.path.relpath(base, a)
        for f in files:
            rr = os.path.join(rel, f) if rel != "." else f
            if ("f/" + rr.replace(os.sep, "/")) in set(excluded):
                continue
            if open(os.path.join(a, rr), "rb").read() != open(os.path.join(b, rr), "rb").read():
                return False
    return True


if __name__ == "__main__":
    sys.exit(main())