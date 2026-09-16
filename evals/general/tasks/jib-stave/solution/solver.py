#!/usr/bin/env python3
"""jib-stave oracle solver.

Repairs the jibblin SDK monorepo's workspace layout so the shipped release
line is consistent again. Strategy, deliberately mirroring what a careful
engineer would do: the committed package-lock.json is the ground truth for
the intended release line, so the resolver refuses to regenerate it and
instead rebuilds every package manifest from it, re-points the published
entrypoints (main/types/exports) at each package's own build output, and
removes stale packaged artifacts (the 1.4-era lib/ snapshot) from the
workspace. Then it runs the full acceptance sequence.

Expected pre-conditions (the shipped, skewed state):
  - packages/scale/package.json declares version 1.2.0 (lockfile says 2.1.0)
  - packages/api/package.json pins @jibblin/scale at 1.2.0 (lockfile ^2.1.0)
  - packages/core/package.json points main/types/exports at lib/ artifacts
    whose API (Token as string, mint/validate/ttl) predates the current
    2.1.0 source (issue/verify/ageSeconds/encodeBase64Url/decodeBase64Url).

The solver is generic: it derives everything from the lockfile and the
existing manifest shape, and it performs no special-casing of the skew beyond
treating the lockfile as authoritative.

Usage: python3 solver.py [ROOT]    (ROOT defaults to /app)
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/app")
LOCK = ROOT / "package-lock.json"
CONSUMER = ROOT / "consumer/tsconfig.json"

ENTRY = {
    "main": "dist/index.js",
    "types": "dist/index.d.ts",
    "exports": {
        ".": {
            "types": "./dist/index.d.ts",
            "require": "./dist/index.js",
            "import": "./dist/index.js",
        }
    },
}


def sh(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        args, cwd=str(ROOT), capture_output=True, text=True
    )


def main() -> int:
    if not LOCK.is_file():
        print("FAIL: no package-lock.json in %s" % ROOT)
        return 1
    lock = json.loads(LOCK.read_text())
    pkgs = lock.get("packages", {})

    # 1. rebuild every workspace manifest from the lockfile.
    for name in ("core", "scale", "api"):
        key = "packages/%s" % name
        rec = pkgs.get(key)
        if rec is None:
            print("FAIL: lockfile has no entry for workspace %r" % name)
            return 1
        path = ROOT / "packages" / name / "package.json"
        man = json.loads(path.read_text())
        man["version"] = rec.get("version", man["version"])
        if rec.get("dependencies"):
            man["dependencies"] = dict(rec["dependencies"])
        # published entrypoints: point at this package's own build output
        man.update(
            {
                "main": ENTRY["main"],
                "types": ENTRY["types"],
                "exports": {
                    ".": {
                        "types": "./" + ENTRY["types"],
                        "require": "./" + ENTRY["main"],
                        "import": "./" + ENTRY["main"],
                    }
                },
            }
        )
        path.write_text(json.dumps(man, indent=2) + "\n")
        print("repaired %s -> version %s" % (key, man["version"]))

    # 2. drop stale packaged artifacts from the workspace (the lib/ snapshot
    #    that shadowed the build output and the hidden consumer surface).
    lib = ROOT / "packages/core/lib"
    if lib.is_dir():
        shutil.rmtree(lib)
        print("removed %s" % lib.relative_to(ROOT))
    elif lib.exists():
        lib.unlink()

    # 3. root manifest is already correct; normalise formatting only.
    root_man = json.loads((ROOT / "package.json").read_text())
    (ROOT / "package.json").write_text(json.dumps(root_man, indent=2) + "\n")

    # 4. run the acceptance sequence from a clean install.
    steps = [
        ["npm", "ci", "--offline", "--no-audit", "--no-fund", "--loglevel=error"],
        ["npm", "run", "build", "-ws"],
        ["npm", "test", "-ws"],
        [str(ROOT / "node_modules/.bin/tsc"), "-p", str(CONSUMER)],
    ]
    for step in steps:
        r = sh(*step)
        if r.returncode != 0:
            print("FAIL: %s" % " ".join(step))
            print((r.stdout or "")[-2000:])
            print((r.stderr or "")[-2000:])
            return 1
        print("ok: %s" % " ".join(step[:2]))
    print("jib-stave oracle: acceptance sequence green")
    return 0


if __name__ == "__main__":
    sys.exit(main())