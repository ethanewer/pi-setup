#!/usr/bin/env python3
"""Independent verifier for drift-forge. Runs at verify time with the agent's
/app deliverables present and /tests mounted read-only (hidden cases under
/tests/hidden). Exits 0 iff every check passes."""
import os, sys, json, re, shutil, subprocess, hashlib, struct
from collections import Counter

OK = True


def fail(msg):
    global OK
    OK = False
    print("FAIL: " + msg)


def read_bytes(p):
    with open(p, "rb") as f:
        return f.read()


def shell(*cmd):
    r = subprocess.run(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return r.returncode, r.stdout, r.stderr


def filepaths(root):
    out = []
    for dp, dns, fns in os.walk(root):
        for fn in fns:
            full = os.path.join(dp, fn)
            if os.path.isfile(full):
                out.append(os.path.relpath(full, root))
    return out


# ---------------- tool 1: normalize_lf ----------------
def verify_norm():
    src, dst = "/tests/hidden/norm/tree", "/tmp/normout"
    if os.path.exists(dst):
        shutil.rmtree(dst)
    rc, _, err = shell("python3", "/app/normalize_lf.py", src, dst)
    if rc != 0:
        fail("normalize_lf exit nonzero: %s" % err[:200])
        return
    inrel = filepaths(src)
    outrel = filepaths(dst)
    if Counter(inrel) != Counter(outrel):
        fail("normalize changed the relative file set")
        return
    for rel in inrel:
        s = read_bytes(os.path.join(src, rel))
        o = read_bytes(os.path.join(dst, rel))
        if b"\x00" in s:
            if o != s:
                fail("normalize modified a binary file: %s" % rel)
        else:
            exp = s.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            if o != exp:
                fail("normalize text wrong for %s" % rel)


# ---------------- tool 2: reshard ----------------
def collect_blobs(root):
    """Assemble a list of the tree's stored contents: whole files as-is and a
    file's .part_NNN chunks reassembled, in numeric order."""
    parts = {}
    plain = []
    for dp, dns, fns in os.walk(root):
        for fn in fns:
            full = os.path.join(dp, fn)
            if not os.path.isfile(full):
                continue
            data = read_bytes(full)
            m = re.match(r"^(.*)\.part_(\d+)$", fn)
            if m:
                parts.setdefault(m.group(1), {})[int(m.group(2))] = data
            else:
                plain.append(data)
    for stem, chunks in parts.items():
        plain.append(b"".join(chunks[i] for i in sorted(chunks)))
    return plain


def verify_reshard(in_dir, out_dir, max_items, max_bytes):
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    rc, _, err = shell("python3", "/app/reshard.py", in_dir, out_dir,
                       str(max_items), str(max_bytes))
    if rc != 0:
        fail("reshard(%s) exit nonzero: %s" % (os.path.basename(in_dir), err[:150]))
        return
    for dp, dns, fns in os.walk(out_dir):
        n = sum(1 for fn in fns if os.path.isfile(os.path.join(dp, fn)))
        if n > max_items:
            fail("reshard(%s) item cap %d>%d in %s" % (os.path.basename(in_dir), n, max_items, dp))
        for fn in fns:
            p = os.path.join(dp, fn)
            if os.path.isfile(p) and len(read_bytes(p)) > max_bytes:
                fail("reshard(%s) byte cap exceeded: %s" % (os.path.basename(in_dir), p))
    orig = Counter(read_bytes(os.path.join(in_dir, p))
                   for p in filepaths(in_dir))
    rebuilt = Counter(collect_blobs(out_dir))
    if orig != rebuilt:
        fail("reshard(%s) content not preserved" % os.path.basename(in_dir))


# ---------------- tool 2b: produced /app/output_tree deliverable ---------
def verify_output_tree():
    # The agent is required to leave /app/output_tree behind by running
    # reshard.py over /app/input_tree with max_items=4, max_bytes=2048.
    root = "/app/output_tree"
    if not os.path.isdir(root):
        fail("/app/output_tree deliverable missing")
        return
    if not any(os.path.isfile(os.path.join(dp, fn))
               for dp, dns, fns in os.walk(root) for fn in fns):
        fail("/app/output_tree is empty")
        return
    # Root holds only shard_* directories (no files directly on the root).
    for fn in sorted(os.listdir(root)):
        p = os.path.join(root, fn)
        if not (os.path.isdir(p) and re.match(r"^shard_\d+$", fn)):
            fail("/app/output_tree has non-shard root entry: %s" % fn)
            return
    max_items, max_bytes = 4, 2048
    for dp, dns, fns in os.walk(root):
        n = sum(1 for fn in fns if os.path.isfile(os.path.join(dp, fn)))
        if n > max_items:
            fail("/app/output_tree item cap %d>%d in %s" % (n, max_items, dp))
        for fn in fns:
            p = os.path.join(dp, fn)
            if os.path.isfile(p) and len(read_bytes(p)) > max_bytes:
                fail("/app/output_tree byte cap exceeded: %s" % p)
    orig = Counter(read_bytes(os.path.join("/app/input_tree", rel))
                   for rel in filepaths("/app/input_tree"))
    rebuilt = Counter(collect_blobs(root))
    if orig != rebuilt:
        fail("/app/output_tree content not preserved from input_tree")


# ---------------- tool 3: order_and_hash ----------------
def reference_manifest(root):
    entries = []
    for rel in sorted(filepaths(root), key=lambda p: p.encode("utf-8")):
        data = read_bytes(os.path.join(root, rel))
        entries.append({"path": rel, "size": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
    return {"entries": entries}


def parse_bundle(b):
    if not b.startswith(b"DRIFT-FM-01\n"):
        raise ValueError("bad bundle magic")
    off = len(b"DRIFT-FM-01\n")
    out = []
    while off < len(b):
        plen = struct.unpack(">I", b[off:off + 4])[0]; off += 4
        path = b[off:off + plen].decode("utf-8"); off += plen
        (sz,) = struct.unpack(">Q", b[off:off + 8]); off += 8
        data = b[off:off + sz]; off += sz
        out.append((path, data))
    return out


def verify_order(root):
    m1, m2 = "/tmp/o_m1.json", "/tmp/o_m2.json"
    rc, _, err = shell("python3", "/app/order_and_hash.py", "manifest", root, m1)
    if rc != 0:
        fail("order manifest exit nonzero (%s): %s" % (root, err[:150]))
        return
    shell("python3", "/app/order_and_hash.py", "manifest", root, m2)
    if read_bytes(m1) != read_bytes(m2):
        fail("manifest not deterministic for %s" % root)
        return
    got = json.load(open(m1))
    if got != reference_manifest(root):
        fail("manifest content mismatch for %s" % root)
    b1, b2 = "/tmp/o_b1", "/tmp/o_b2"
    rc, _, err = shell("python3", "/app/order_and_hash.py", "bundle", root, b1)
    if rc != 0:
        fail("bundle exit nonzero (%s): %s" % (root, err[:150]))
        return
    shell("python3", "/app/order_and_hash.py", "bundle", root, b2)
    d1 = read_bytes(b1)
    if d1 != read_bytes(b2):
        fail("bundle not byte-reproducible for %s" % root)
        return
    entries = parse_bundle(d1)
    want_paths = sorted(filepaths(root), key=lambda p: p.encode("utf-8"))
    if [e[0] for e in entries] != want_paths:
        fail("bundle ordering mismatch for %s" % root)
    for path, data in entries:
        if data != read_bytes(os.path.join(root, path)):
            fail("bundle content mismatch for %s:%s" % (root, path))


# ---------------- tool 4: parse_fw ----------------
def verify_parse():
    base = "/tests/hidden/parse"
    for case in sorted(os.listdir(base)):
        d = os.path.join(base, case)
        outp = "/tmp/p_out.json"
        rc, _, err = shell("python3", "/app/parse_fw.py", os.path.join(d, "input.rec"), outp)
        if rc != 0:
            fail("parse_fw exit nonzero (%s): %s" % (case, err[:150]))
            continue
        got = json.load(open(outp))
        exp = json.load(open(os.path.join(d, "expected.json")))
        if got != exp:
            fail("parse case %s mismatch (summary got=%s exp=%s)" % (
                case, got.get("summary"), exp.get("summary")))


# ---------------- main ----------------
def main():
    for scr in ["normalize_lf.py", "reshard.py", "order_and_hash.py", "parse_fw.py"]:
        p = "/app/" + scr
        if not (os.path.isfile(p) and os.access(p, os.X_OK)):
            fail("deliverable missing/not executable: %s" % p)

    if os.path.isfile("/app/manifest.json"):
        got = json.load(open("/app/manifest.json"))
        if got != reference_manifest("/app/seed_tree"):
            fail("manifest.json mismatch over seed_tree")
    else:
        fail("manifest.json missing")

    verify_output_tree()

    verify_reshard("/app/input_tree", "/tmp/rs_fix", 4, 2048)
    verify_reshard("/tests/hidden/reshard/A", "/tmp/rsA", 2, 4096)
    verify_reshard("/tests/hidden/reshard/B", "/tmp/rsB", 3, 1000)
    verify_reshard("/tests/hidden/reshard/C", "/tmp/rsC", 2, 64)
    verify_reshard("/tests/hidden/reshard/D", "/tmp/rsD", 5, 100)

    verify_norm()
    verify_order("/tests/hidden/order/tree")
    verify_order("/tests/hidden/order2/pkg")

    verify_parse()

    print("RESULT:", "PASS" if OK else "FAIL")
    sys.exit(0 if OK else 1)


if __name__ == "__main__":
    main()