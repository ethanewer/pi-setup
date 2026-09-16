"""Build-time self-check for the cistern fixture.

Proves, inside the image build, every property the task relies on:

  R1  the shipped LOOSE tree type-checks with the shipped tsconfig;
  R2  the shipped LOOSE tree is green under vitest (node_modules ready);
  R3  the STRICT rendering type-checks with strict + hardening on;
  R4  the LOOSE tree FAILS that strict check (the migration is real);
  R5  the repository size floors are met.

Runs only at image build time; not shipped in the final image.
"""

import json
import os
import shutil
import subprocess
import sys

GEN = os.path.dirname(os.path.abspath(__file__))
ROOT = sys.argv[1] if len(sys.argv) > 1 else "/app/cistern"
WORK = "/tmp/cistern-selfcheck"

FAILED = []


def check(name, cond, detail=""):
    flag = "ok" if cond else "FAIL"
    print("[%s] %s %s" % (flag, name, detail))
    if not cond:
        FAILED.append(name)


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def main():
    sys.path.insert(0, GEN)
    from assemble import build_repo, dump, HARDENING_FLAGS, TSCONFIG_LOOSE

    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)

    loose = os.path.join(WORK, "loose")
    strict = os.path.join(WORK, "strict")
    os.makedirs(loose)
    os.makedirs(strict)
    build_repo(loose, "loose")
    build_repo(strict, "strict")

    tsc = [os.path.join(ROOT, "node_modules", ".bin", "tsc")]
    exe = os.path.join(ROOT, "node_modules", ".bin", "tsc")
    if not os.path.exists(exe):
        exe = os.path.join(ROOT, "node_modules/.bin/tsc")

    # --- hardened strict config (same as the verifier overlay) ---
    hard = dict(TSCONFIG_LOOSE)
    opts = dict(hard["compilerOptions"])
    opts["strict"] = True
    opts["strictNullChecks"] = True
    opts["noImplicitAny"] = True
    for f in HARDENING_FLAGS:
        opts[f] = True
    hard["compilerOptions"] = opts
    hard["include"] = ["src", "tests"]
    for root_dir in (loose, strict):
        with open(os.path.join(root_dir, "tsconfig.hard.json"), "w") as fh:
            json.dump(hard, fh)

    # R1 loose type-checks under the shipped tsconfig
    r = run([exe, "--noEmit", "-p", "tsconfig.json"], loose)
    check("R1 loose tsc green", r.returncode == 0, r.stdout[-200:])

    # R2 loose suite green
    vitest = os.path.join(ROOT, "node_modules", ".bin", "vitest")
    for root_dir in (loose, strict):
        os.makedirs(os.path.join(root_dir, "node_modules"), exist_ok=True)
        for link in ("vitest", "vite", ".bin", "esbuild", "rollup", "vite-node"):
            src = os.path.join(ROOT, "node_modules", link)
            dst = os.path.join(root_dir, "node_modules", link)
            if os.path.exists(src) and not os.path.exists(dst):
                os.symlink(src, dst)
    r = run([vitest, "run", "--reporter=dot"], loose)
    check("R2 loose vitest green", r.returncode == 0, r.stdout[-300:])

    # R3 strict rendering compiles under hardening
    r = run([exe, "--noEmit", "-p", "tsconfig.hard.json"], strict)
    check("R3 strict+hardened tsc green", r.returncode == 0, r.stdout[-300:])

    # R4 loose tree must FAIL the hardened strict check
    r = run([exe, "--noEmit", "-p", "tsconfig.hard.json"], loose)
    errors = r.stdout.count("error TS")
    check("R4 loose fails strict (errors=%d)" % errors, r.returncode != 0 and errors >= 30, "")

    # R5 size floor
    def loc(root_dir):
        total = 0
        for base, _dirs, files in os.walk(os.path.join(root_dir, "src")):
            for f in files:
                if f.endswith(".ts"):
                    with open(os.path.join(base, f), encoding="utf-8") as fh:
                        total += sum(1 for _ in fh)
        for base, _dirs, files in os.walk(os.path.join(root_dir, "tests")):
            for f in files:
                if f.endswith(".ts"):
                    with open(os.path.join(base, f), encoding="utf-8") as fh:
                        total += sum(1 for _ in fh)
        return total

    for mode, root_dir in (("loose", loose), ("strict", strict)):
        n = loc(root_dir)
        check("R5 %s LOC=%d" % (mode, n), n >= 5000, "")

    if FAILED:
        print("SELFCHECK FAILURES: %s" % ", ".join(FAILED))
        return 1
    print("SELFCHECK OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())