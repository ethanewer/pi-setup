#!/usr/bin/env python3
"""Build the hydrawatch source-release archives used by the calm-canyon task.

Author of clean-room fixtures only. Produces:
  * environment/files/payload/  (visible release 2029.55.0)
  * tests/hidden/fetch/rel2029.52.1-g/   (valid hidden release, H1)
  * tests/hidden/fetch/rel2029.41.7-b/   (bad-checksum store, H2)

Each release dir archives one hydrawatch source tree with a root-level
MANIFEST.json (relpath -> sha256) that bin/verify_extract.py checks.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE_SRC = "/tmp/hydrasrc"
TASKDIR = HERE  # running from tasks/calm-canyon


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def build_release(srcdir, outdir, version):
    """Create tarball (into outdir) with MANIFEST.json + checksum + current.txt."""
    assert os.path.isdir(srcdir)
    # 1) collect files (exclude MANIFEST.json if regenerating)
    entries = {}
    for dirpath, _dn, fns in os.walk(srcdir):
        for fn in fns:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, srcdir)
            if rel == "MANIFEST.json":
                continue
            entries[rel] = sha256(full)
    manifest = {"release": version, "files": dict(sorted(entries.items()))}
    mani_path = os.path.join(srcdir, "MANIFEST.json")
    with open(mani_path, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)

    archive = os.path.join(outdir, "hydrawatch-src-%s.tgz" % version)
    os.makedirs(outdir, exist_ok=True)
    subprocess.run(
        ["tar", "-C", srcdir, "-czf", archive, "."], check=True)
    a_sha = sha256(archive)
    with open(os.path.join(outdir, "checksum.sha256"), "w") as f:
        f.write("%s  %s\n" % (a_sha, os.path.basename(archive)))
    with open(os.path.join(outdir, "current.txt"), "w") as f:
        f.write(os.path.basename(archive) + "\n")
    # manifest must NOT be in the payload manifest's own listing; remove it from srcdir
    os.remove(mani_path)
    return os.path.basename(archive), a_sha


def main():
    taskdir = HERE
    vis = os.path.join(HERE, "environment", "files", "payload")
    os.makedirs(vis, exist_ok=True)
    name_vis, sha_vis = build_release(BASE_SRC, vis, "2029.55.0")
    print("visible archive:", name_vis, sha_vis, "at", vis)

    # hidden good release (v2029.52.1): clone tree, tweak version string
    hs = "/tmp/hydsrc_hidden"
    if os.path.isdir(hs):
        shutil.rmtree(hs)
    shutil.copytree(BASE_SRC, hs)
    # tweak a file so versioning differs (content change)
    readme = os.path.join(hs, "README.md")
    txt = open(readme).read().replace("2029.55.0", "2029.52.1")
    open(readme, "w").write(txt)
    ctrl = os.path.join(hs, "debian", "changelog")
    ctxt = open(ctrl).read().replace("2029.55.0", "2029.52.1")
    open(ctrl, "w").write(ctxt)
    h1 = os.path.join(taskdir, "tests", "hidden", "fetch", "rel2029.52.1")
    build_release(hs, h1, "2029.52.1")
    print("H1 good hidden release ->", h1)

    # H2 bad: valid archive + WRONG checksum so fetch must reject
    hs2 = "/tmp/hydsrc_hidden2"
    if os.path.isdir(hs2):
        shutil.rmtree(hs2)
    shutil.copytree(BASE_SRC, hs2)
    c = os.path.join(hs2, "debian", "changelog")
    open(c, "w").write(open(c).read().replace("2029.55.0", "2029.41.7"))
    h2 = os.path.join(taskdir, "tests", "hidden", "fetch", "rel2029.41.7-bad")
    name2, _sha2 = build_release(hs2, h2, "2029.41.7")
    # overwrite the checksum with a wrong hash
    with open(os.path.join(h2, "checksum.sha256"), "w") as f:
        f.write("%064d  %s\n" % (0, name2))
    print("H2 bad hidden store ->", h2)


if __name__ == "__main__":
    main()