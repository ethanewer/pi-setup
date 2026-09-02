#!/usr/bin/env python3
"""One-shot fixture generator for kite-helix (visible + hidden cases)."""
import os, gzip, zipfile, hashlib, pathlib, shutil

BASE = pathlib.Path(__file__).resolve().parent
VIS = BASE / "environment" / "files" / "data"
HID = BASE / "tests" / "hidden"


def deep_string(seed, n):
    s = seed
    while len(s) < n:
        s = s[:] + s[::-1]
    return s[:n]


def make_token_archive(manifest, token, decoys):
    manifest.mkdir(parents=True, exist_ok=True)
    members = {
        # the wanted member: exact path must be surface-able by listing the archive
        "manifest/release/current/config.yaml":
            "profile: prod\napp_token: %s\nregion: us-e\n" % token,
        "manifest/release/staging/config.yaml":
            "profile: stag\napp_token: %s\n" % decoys[0],
        "manifest/backup/current/config.yaml":
            "profile: bak\napp_token: %s\n" % decoys[1],
        "manifest/release/expr/config.yaml":
            "profile: expr\napp_token: %s-probe\n" % token,
        "manifest/release/current/build.log": "[info] signed ok\n",
        "manifest/RELEASE_NOTES.txt": "release %s next\n" % token,
    }
    with zipfile.ZipFile(manifest / "artifact.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for n, c in members.items():
            z.writestr(n, c)


def make_pkg(pkg):
    pkg.mkdir(parents=True, exist_ok=True)
    (pkg / "main.py").write_text("print('hi')\n")
    (pkg / "README.md").write_text("# rites\n")
    lib = pkg / "lib"; lib.mkdir(exist_ok=True)
    (lib / "util.py").write_text("def u():\n    return 1\n")
    (lib / "util.pyc").write_bytes(b"\x00\x01bogus")
    (lib / "dep.py").write_text("import os\n")
    v = pkg / "vendor"; v.mkdir(exist_ok=True)
    (v / "bundle.js").write_text("vendor code\n")
    py = pkg / "__pycache__"; py.mkdir(exist_ok=True)
    (py / "main.cpython-312.pyc").write_bytes(b"PYC")
    t = pkg / "tools"; t.mkdir(exist_ok=True)
    (t / "runner.o").write_bytes(b"\x7fELF")
    (t / "watch.cache").write_bytes(b"cache")
    cf = pkg / "config"; cf.mkdir(exist_ok=True)
    (cf / "main.toml").write_text("port = 8080\n")
    # restricted-permission: mode 000 must be excluded
    cred = pkg / "credentials" / "secret.keys"
    cred.parent.mkdir(exist_ok=True)
    cred.write_text("TOPSECRET")
    os.chmod(cred, 0o000)
    # must-be-kept precision probes
    (pkg / "vendor.py").write_text("def ok(): pass\n")           # file, not dir  -> keep
    (pkg / "compile.tmp.txt").write_text("kept\n")               # ends .txt      -> keep
    (pkg / "tool.o.txt").write_text("kept\n")


def make_deep(d):
    d.mkdir(parents=True, exist_ok=True)
    long_dirs = [
        "marshy_edgeproc_backplane_aqueduct_dispatch_summary_sys",
        "verdant_quilting_machinist_annunciator_systemic_lattice_x",
        "obfuscated_transitional_steganographic_verum_fenestration",
        "corinthian_meridian_subcoastal_aberration_transcript_arc",
    ]
    node = d
    for seg in long_dirs:
        node = node / seg
        node.mkdir(exist_ok=True)
    blob = node / deep_string("plasma", 70)
    blob.write_text("deep data token rlx\n")

    # single file name well over 100 chars
    longf = deep_string("fulcrum", 168)
    rd = d / "rolling_layers" / "northwind"
    rd.mkdir(parents=True, exist_ok=True)
    (rd / longf).write_text("LONGNAME-LINE\n")

    # symlink (relative target) that must be preserved as a symlink
    link_dir = d / "link"; link_dir.mkdir(exist_ok=True)
    target = d / "archives" / "current" / "snapshot" / "release.blob"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(b"\x00release-payload\x00")
    rel = os.path.relpath(target, link_dir)
    (link_dir / "release_alias").symlink_to(rel)


def make_mirror(ms, pairs):
    ms.mkdir(parents=True, exist_ok=True)
    for rel, raw in pairs.items():
        p = ms / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(gzip.compress(raw.encode()))


def make_hash(hr, files):
    hr.mkdir(parents=True, exist_ok=True)
    for rel, content in files.items():
        p = hr / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)


def build(data, token, mirror, hashfiles):
    if data.exists():
        shutil.rmtree(data)
    data.mkdir(parents=True, exist_ok=True)
    make_token_archive(data / "manifest", token, [token + "-d1", token + "-d2"])
    make_pkg(data / "pkg")
    make_deep(data / "deep")
    make_mirror(data / "mirror_src", mirror)
    make_hash(data / "hash", hashfiles)


def deep_string_loader(seed, n):
    s = seed
    while len(s) < n:
        s = s + seed
    return s[:n]


def main():
    build(VIS, "rlz-7f3a-91cd-2e",
          {"gen/plain.dat.gz": "PLAINDATA-1\n",
           "gen/twin.dat.gz": "TWINE-amount\n",
           "beta/deep/omega.dat.gz": "OMEGA-9 payload\n"},
          {"root.txt": "hello root\n",
           "sub/numbers.dat": "1\n2\n3\n",
           "sub/deep/gamma.json": '{"g":true}\n',
           "other/alpha.tsv": "a\tb\n",
           "src/with space.txt": "spaces\n"})

    build(HID / "0" / "data", "wire-11-aa-bb",
          {"ch/month.dat.gz": "month-4\n",
           "ch/sun.dat.gz": "sun-8\n",
           "lab/phase.dat.gz": "phase-gamma\n",
           "lab/phase2.dat.gz": "phase-delta\n"},
          {"L1/a.txt": "aa\n",
           "N2/b.tsv": "x\ty\n",
           "deep/well/c.txt": "ccc\n"})

    build(HID / "1" / "data", "edge-5.1.2",
          {"only/uniq.dat.gz": "single\n",
           "group/many.dat.gz": "many-12\n"},
          {"plain.txt": "e\n",
           "dir/file.bin" : "binary\x00\x01\n",
           "weird/na me.txt": "sp\n"})

    build(HID / "2" / "data", "hal-0x9f-77",
          {"pack/a.dat.gz": "a\n",
           "pack/deep/b.dat.gz": "bb\n",
           "alone/c.dat.gz": "ccc\n"},
          {"z/a.txt": "z\n",
           "y/deep/b.txt": "yb\n"})


if __name__ == "__main__":
    main()