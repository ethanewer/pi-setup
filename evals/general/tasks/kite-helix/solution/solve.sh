#!/usr/bin/env bash
# kite-helix oracle: author the real /app/solve.py then run it to produce
# /app/out and /app/answer.json. Never reads /tests or /solution.
set -euo pipefail

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""kite-helix: release-archive triage on a workspace directory.

Usage: python3 solve.py <workdir>
The workdir must contain ./data with the five fixture inputs and receives
./out and ./answer.json as outputs.
"""
import re, sys, os, json, gzip, hashlib, zipfile, tarfile, pathlib

EXCLUDE_ENDINGS = (".pyc", ".o", ".tmp", ".cache")
EXCLUDE_DIRS = ("vendor", "__pycache__")
TARGET_MEMBER = "manifest/release/current/config.yaml"


def excluded(rel: str, real_path: "pathlib.Path") -> bool:
    """Rule used for packaging: the shipped archive must drop these entries."""
    parts = pathlib.PurePosixPath(rel).parts
    name = parts[-1]
    if any(c in parts for c in EXCLUDE_DIRS):
        return True
    if name.endswith(EXCLUDE_ENDINGS):
        return True
    try:
        mode = real_path.stat().st_mode & 0o700
    except OSError:
        return True
    return mode == 0  # restricted-permission files (not readable by owner)


def main(ws) -> None:
    ws = pathlib.Path(ws).resolve()
    data = ws / "data"
    out = ws / "out"
    out.mkdir(parents=True, exist_ok=True)

    # -- 1. surface the wanted archive member ---------------------------------
    art = data / "manifest" / "artifact.zip"
    with zipfile.ZipFile(art) as z:
        members = z.namelist()            # list the table of contents
        wanted = [n for n in members if n == TARGET_MEMBER]
        assert wanted, "target member missing from archive"
        cfg = z.read(wanted[0]).decode()
    m = re.search(r"^\s*app_token\s*[:=]\s*[\"']?([^\s\"']+)", cfg, re.M)
    token = m.group(1)

    # -- 2. package data/pkg -> out/release.zip with exclusions ---------------
    pkg = data / "pkg"
    rzip = out / "release.zip"
    shipped = []
    with zipfile.ZipFile(rzip, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(pkg):
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
            for f in files:
                fp = pathlib.Path(root) / f
                rel = fp.relative_to(pkg).as_posix()
                if excluded(rel, fp):
                    continue
                z.write(fp, rel)
                shipped.append(rel)

    # -- 3. bundle data/deep preserving symlinks + long/deep names ------------
    with tarfile.open(out / "deep.tar.gz", "w:gz",
                      format=tarfile.PAX_FORMAT) as t:
        # PAX_FORMAT stores long/deep member names; add() below preserves
        # symlinks as links (it lstats rather than following).
        t.add(data / "deep", arcname="deep")

    # -- 4. mirror: decompress every .dat.gz under mirror_src ----------------
    mout = out / "mirror"
    mout.mkdir(parents=True, exist_ok=True)
    for full in (data / "mirror_src").rglob("*.dat.gz"):
        raw = gzip.decompress(full.read_bytes())
        name = full.name[:-3]  # strip ".gz"
        (mout / name).write_bytes(raw)

    # -- 5. hash every file under data / hash (relative names) ---------------
    hr = data / "hash"
    hmap = {}
    for full in sorted(hr.rglob("*")):
        if full.is_file():
            rel = full.relative_to(hr).as_posix()
            hmap[rel] = hashlib.sha256(full.read_bytes()).hexdigest()

    answer = {
        "token": token,
        "hash": hmap,
        "release_members": sorted(shipped),
        "algorithm": "sha256",
    }
    (ws / "answer.json").write_text(json.dumps(answer, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
PYEOF

chmod +x /app/solve.py
python3 /app/solve.py /app