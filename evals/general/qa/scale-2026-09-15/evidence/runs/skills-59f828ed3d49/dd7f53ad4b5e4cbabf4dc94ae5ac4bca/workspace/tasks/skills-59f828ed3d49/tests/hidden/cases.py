import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

APP = os.environ.get("MANIFEST_AUDIT_APP", "/app/manifest_audit.py")


def run(root, manifest, *args):
    return subprocess.run(
        [sys.executable, APP, "audit", "--root", str(root), *args, str(manifest)],
        text=True, capture_output=True
    )


def record(path, data):
    return {"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def main():
    with tempfile.TemporaryDirectory() as td:
        base = Path(td)
        root = base / "root"
        root.mkdir()
        (root / "a.txt").write_bytes(b"alpha")
        (root / "sub").mkdir()
        (root / "sub" / "b.py").write_bytes(b"print(1)\n")
        good = base / "good.json"
        good.write_text(json.dumps({"files": [record("sub/b.py", b"print(1)\n"), record("a.txt", b"alpha")] }))

        p = run(root, good)
        assert p.returncode == 0, (p.returncode, p.stderr)
        assert p.stderr == ""
        assert json.loads(p.stdout) == {"ok": True, "checked": 2, "errors": []}

        bad = base / "bad.json"
        wrong = record("a.txt", b"wrong")
        wrong["bytes"] = 99
        bad.write_text(json.dumps({"files": [wrong, record("../secret", b"x"), record("a.txt", b"alpha")] }))
        p = run(root, bad)
        assert p.returncode == 2
        report = json.loads(p.stdout)
        codes = [x["code"] for x in report["errors"]]
        assert {"BYTE_MISMATCH", "HASH_MISMATCH", "PATH_TRAVERSAL", "DUPLICATE_PATH"} <= set(codes)
        assert report["errors"] == sorted(report["errors"], key=lambda x: (x["path"], x["code"], x["detail"]))

        outside = base / "outside.txt"
        outside.write_text("private")
        try:
            (root / "escape.txt").symlink_to(outside)
        except (OSError, NotImplementedError):
            pass
        else:
            symlink = base / "symlink.json"
            symlink.write_text(json.dumps({"files": [record("escape.txt", b"private")] }))
            p = run(root, symlink)
            assert p.returncode == 2 and "SYMLINK_ESCAPE" in {x["code"] for x in json.loads(p.stdout)["errors"]}

        policy = base / "policy.json"
        policy.write_text(json.dumps({"allowed_extensions": [".py"], "max_bytes": 3,
                                       "required_paths": ["a.txt"], "forbidden_paths": ["sub/b.py"]}))
        p = run(root, good, "--policy", str(policy))
        assert p.returncode == 2
        codes = {x["code"] for x in json.loads(p.stdout)["errors"]}
        assert {"EXTENSION_FORBIDDEN", "SIZE_LIMIT", "PATH_FORBIDDEN"} <= codes

        out = base / "report.txt"
        p = run(root, good, "--format", "text", "--output", str(out))
        assert p.returncode == 0 and p.stdout == "" and p.stderr == ""
        assert out.read_text() == "OK\nchecked: 2\n"
        before = good.read_text()
        p = run(root, good, "--output", str(good))
        assert p.returncode != 0 and good.read_text() == before

        malformed = base / "malformed.json"
        malformed.write_text("[")
        p = run(root, malformed)
        assert p.returncode == 2
        assert json.loads(p.stdout)["errors"][0]["code"] == "INVALID_MANIFEST"


if __name__ == "__main__":
    main()
