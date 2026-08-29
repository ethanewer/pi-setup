#!/bin/bash
# meadow-bridge oracle: writes the real pipeline implementation and runs it
# on the visible inputs. Never reads the verifier tree.
set -eu

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""Release archive audit pipeline: targeted extraction, pruned mirror,
ISO9660 embed, POSIX ACL share, PBKDF2 hash map, prefix-safe relocation."""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def relocate(path, src_prefix, dst_prefix):
    base = src_prefix.rstrip("/")
    if path.rstrip("/") == base:
        return dst_prefix
    if path.startswith(base + "/"):
        return dst_prefix.rstrip("/") + path[len(base):]
    return path


def main():
    if len(sys.argv) != 4:
        die("usage: solve.py TAR CONFIG OUTDIR")
    tar_path, config_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(config_path, encoding="utf-8") as f:
        config = json.load(f)
    os.makedirs(out_dir, exist_ok=True)

    with tarfile.open(tar_path, "r:gz") as tf:
        members = [m for m in tf.getmembers()]
        target = None
        for m in members:
            if not m.isdir() and config["target_pattern"] in m.name:
                target = m.name
                break
        if target is None:
            die("no member matches target_pattern")
        # targeted extraction
        tf2 = tarfile.open(tar_path, "r:gz")
        data = tf2.extractfile(target).read()
        tf2.close()
        with open(os.path.join(out_dir, "extracted.bin"), "wb") as f:
            f.write(data)
        # pruned mirror
        mirror = os.path.join(out_dir, "mirror")
        if os.path.exists(mirror):
            shutil.rmtree(mirror)
        pruned = [m for m in members
                  if not any(p in m.name for p in config["prune_patterns"])]
        tf3 = tarfile.open(tar_path, "r:gz")
        tf3.extractall(mirror, members=pruned, filter="fully_trusted")
        tf3.close()

    pkg_root = os.path.join(mirror, "pkg")
    symlinks = 0
    hashes = {}
    for dirpath, dirnames, filenames in os.walk(pkg_root):
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, pkg_root)
            if os.path.islink(p):
                symlinks += 1
                continue
            with open(p, "rb") as f:
                blob = f.read()
            hashes[rel] = hashlib.pbkdf2_hmac(
                "sha256", blob, config["salt"].encode(),
                config["iterations"]).hex()

    # ISO9660 embed of the toolchain directory
    toolchain = os.path.join(pkg_root, "toolchain")
    iso_path = os.path.join(out_dir, "release.iso")
    subprocess.run(
        ["genisoimage", "-o", iso_path, "-R", "-J", "-quiet", toolchain],
        check=True)

    # shared directory with live + default ACLs
    shared = os.path.join(out_dir, "shared")
    os.makedirs(shared, exist_ok=True)
    grp = config["acl_group"]
    subprocess.run(["setfacl", "-m", f"g:{grp}:rx", shared], check=True)
    subprocess.run(["setfacl", "-d", "-m", f"g:{grp}:rx", shared], check=True)

    relocations = {p: relocate(p, config["src_prefix"], config["dst_prefix"])
                   for p in config["paths"]}

    answer = {
        "extracted": target,
        "symlinks_preserved": symlinks,
        "file_count": len(hashes),
        "hashes": hashes,
        "relocations": relocations,
        "iso_size": os.path.getsize(iso_path),
        "acl": {"group": grp, "shared_dir": shared},
    }
    with open(os.path.join(out_dir, "answer.json"), "w", encoding="utf-8") as f:
        json.dump(answer, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
PYEOF
chmod +x /app/solve.py

# visible run: produces /app/out/answer.json plus mirror, release.iso, shared/
python3 /app/solve.py /app/release.tar.gz /app/config.json /app/out
