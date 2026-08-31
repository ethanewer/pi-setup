#!/usr/bin/env python3
"""dunlin-key verifier (executes-deliverable).

Executes /app/pack_index.py on the visible tree and on hidden trees, checks
deterministic member ordering, schema purity (no owner/host/timestamp fields),
fixed ZIP member metadata, and byte-identity across repeated runs and across
mtime-shifted / re-ordered copies of the same trees. Writes reward (0/1) to
/logs/verifier/reward.txt.
"""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

REW = "/logs/verifier/reward.txt"
PACK = "/app/pack_index.py"
VISIBLE = "/app/fw_tree"
FORMAT = "fw-bundle-index-1"

# Pristine digest of the shipped /app/fw_tree (sorted relpath + bytes), to
# enforce the no-modify rule.
PRISTINE_TREE_DIGEST = "d55a303525b8a4631e788bd1876a9b70a2ea63c6bffbb7249e4e45d2ac0ccacb"

failures = []


def fail(msg):
    failures.append(msg)


def run_tool(sub, indir, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, PACK, sub, indir, out_path],
            capture_output=True, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        fail("pack_index.py %s timed out on %s" % (sub, indir))
        return False
    if r.returncode != 0:
        fail("pack_index.py %s exited %d on %s: %s"
             % (sub, r.returncode, indir, r.stderr[-300:]))
        return False
    return os.path.isfile(out_path)


def list_regular(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            out.append(os.path.relpath(full, root))
    return out


def expected_entries(root):
    ents = []
    for rel in sorted(list_regular(root)):
        with open(os.path.join(root, rel), "rb") as fh:
            data = fh.read()
        ents.append({"path": rel, "size": len(data),
                     "sha256": hashlib.sha256(data).hexdigest()})
    return ents


def tree_digest(root):
    h = hashlib.sha256()
    for rel in sorted(list_regular(root)):
        with open(os.path.join(root, rel), "rb") as fh:
            h.update(rel.encode("utf-8") + b"\x00" + fh.read() + b"\n")
    return h.hexdigest()


def make_mtime_shifted_copy(src):
    """Copy a tree with reversed creation order and shifted mtimes."""
    dst = tempfile.mkdtemp(prefix="dk_shift_")
    for rel in sorted(list_regular(src), reverse=True):
        target = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(os.path.join(src, rel), target)
        os.utime(target, (1234567890, 1234567890))
    return dst


def check_index_outputs(root, label):
    """Run index twice; validate schema, ordering, and cross-run identity."""
    o1 = os.path.join(tempfile.mkdtemp(prefix="dk_idx_"), "i1.json")
    o2 = os.path.join(tempfile.mkdtemp(prefix="dk_idx_"), "i2.json")
    if not run_tool("index", root, o1) or not run_tool("index", root, o2):
        return
    with open(o1, "rb") as fh:
        b1 = fh.read()
    with open(o2, "rb") as fh:
        b2 = fh.read()
    if b1 != b2:
        fail("%s: index output not byte-identical across two runs" % label)
    try:
        obj = json.loads(b1.decode("utf-8"))
    except Exception as exc:
        fail("%s: index output is not valid UTF-8 JSON: %s" % (label, exc))
        return
    if not isinstance(obj, dict) or set(obj.keys()) != {"entries", "format"}:
        fail("%s: index top-level keys must be exactly {entries, format}, "
             "got %s" % (label, sorted(obj.keys()) if isinstance(obj, dict) else obj))
        return
    if obj["format"] != FORMAT:
        fail("%s: index format must be %r" % (label, FORMAT))
    ents = obj["entries"]
    want = expected_entries(root)
    if ents != want:
        fail("%s: index entries differ from independently derived expected "
             "(check byte-order sorting, schema keys, sha256)" % label)
    for e in ents if isinstance(ents, list) else []:
        if not isinstance(e, dict) or set(e.keys()) != {"path", "size", "sha256"}:
            fail("%s: entry has unexpected keys %s" % (label, sorted(e.keys())))
            break
    return o1


def check_pack_outputs(root, label):
    """Run pack twice; validate structure, metadata, cross-run identity."""
    t = tempfile.mkdtemp(prefix="dk_zip_")
    z1, z2 = os.path.join(t, "b1.zip"), os.path.join(t, "b2.zip")
    if not run_tool("pack", root, z1) or not run_tool("pack", root, z2):
        return
    with open(z1, "rb") as fh:
        b1 = fh.read()
    with open(z2, "rb") as fh:
        b2 = fh.read()
    if b1 != b2:
        fail("%s: pack output not byte-identical across two runs" % label)
    try:
        zf = zipfile.ZipFile(z1)
    except Exception as exc:
        fail("%s: pack output is not a valid ZIP: %s" % (label, exc))
        return
    names = zf.namelist()
    want = sorted(list_regular(root))
    if names != want:
        fail("%s: ZIP member order %s != expected byte-sorted %s"
             % (label, names, want))
    for info in zf.infolist():
        if info.date_time != (1980, 1, 1, 0, 0, 0):
            fail("%s: member %r date_time %s != fixed (1980,1,1,0,0,0)"
                 % (label, info.filename, info.date_time))
        if info.compress_type != zipfile.ZIP_STORED:
            fail("%s: member %r not ZIP_STORED" % (label, info.filename))
        if info.external_attr != 0o600 << 16:
            fail("%s: member %r carries non-default host metadata "
                 "(external_attr=%r; use a fresh ZipInfo, not "
                 "ZipFile.write/from_file)" % (label, info.filename, info.external_attr))
        if info.extra not in (b"",) or info.comment not in (b"",):
            fail("%s: member %r has extra bytes or a comment" % (label, info.filename))
        want_data = open(os.path.join(root, info.filename), "rb").read()
        if zf.read(info.filename) != want_data:
            fail("%s: member %r bytes differ from source file" % (label, info.filename))
    if zf.comment not in (b"",):
        fail("%s: archive comment must be empty" % label)
    return z1


def main():
    # --- deliverable script contract ---------------------------------------
    if not os.path.isfile(PACK):
        fail("missing /app/pack_index.py")
        finish()
        return
    mode = os.stat(PACK).st_mode
    if not (mode & stat.S_IXUSR):
        fail("/app/pack_index.py is not executable (chmod +x)")
    with open(PACK, "rb") as fh:
        if not fh.readline().startswith(b"#!"):
            fail("/app/pack_index.py missing #! shebang on line 1")

    # --- no-modify guard on the shipped tree --------------------------------
    if not os.path.isdir(VISIBLE) or tree_digest(VISIBLE) != PRISTINE_TREE_DIGEST:
        fail("/app/fw_tree missing or modified")

    # --- visible tree: fresh runs + deliverable artifacts --------------------
    idx_path = check_index_outputs(VISIBLE, "visible")
    zip_path = check_pack_outputs(VISIBLE, "visible")
    if idx_path and os.path.isfile("/app/index.json"):
        with open(idx_path, "rb") as a, open("/app/index.json", "rb") as b:
            if a.read() != b.read():
                fail("visible: /app/index.json differs from a fresh index run")
    elif not os.path.isfile("/app/index.json"):
        fail("missing /app/index.json")
    if zip_path and os.path.isfile("/app/bundle.zip"):
        with open(zip_path, "rb") as a, open("/app/bundle.zip", "rb") as b:
            if a.read() != b.read():
                fail("visible: /app/bundle.zip differs from a fresh pack run")
    elif not os.path.isfile("/app/bundle.zip"):
        fail("missing /app/bundle.zip")

    # --- hidden trees: ordering + identity under mtime/creation shifts -------
    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        fail("no hidden cases present")
    for case in cases:
        tree = os.path.join(hidden, case, "tree")
        if not os.path.isdir(tree):
            fail("hidden '%s' malformed (no tree/)" % case)
            continue
        check_index_outputs(tree, "hidden '%s'" % case)
        check_pack_outputs(tree, "hidden '%s'" % case)
        shifted = make_mtime_shifted_copy(tree)
        try:
            i1 = os.path.join(tempfile.mkdtemp(prefix="dk_x_"), "a.json")
            i2 = os.path.join(tempfile.mkdtemp(prefix="dk_x_"), "b.json")
            z1 = os.path.join(tempfile.mkdtemp(prefix="dk_x_"), "a.zip")
            z2 = os.path.join(tempfile.mkdtemp(prefix="dk_x_"), "b.zip")
            if all(run_tool(s, t, o) for s, t, o in
                   (("index", tree, i1), ("index", shifted, i2),
                    ("pack", tree, z1), ("pack", shifted, z2))):
                if open(i1, "rb").read() != open(i2, "rb").read():
                    fail("hidden '%s': index bytes change under mtime/creation "
                         "shift (not deterministic)" % case)
                if open(z1, "rb").read() != open(z2, "rb").read():
                    fail("hidden '%s': bundle bytes change under mtime/creation "
                         "shift (host metadata leaked?)" % case)
        finally:
            shutil.rmtree(shifted, ignore_errors=True)

    # --- synthesized empty tree ----------------------------------------------
    empty = tempfile.mkdtemp(prefix="dk_empty_")
    check_index_outputs(empty, "empty")
    check_pack_outputs(empty, "empty")
    os.rmdir(empty)

    finish()


def finish():
    print("verify failures:", failures)
    reward = 1 if not failures else 0
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REW, "w") as fh:
        fh.write(str(reward))
    sys.exit(0 if reward else 1)


if __name__ == "__main__":
    main()
