"""Hidden-case checker for prism-anchor.

Usage: python3 /tests/hidden/checker.py <case_dir>

Each case dir has input/scenario.json (a variant / missing / malformed manifest)
and input/examples_extra.json (fresh normalize() cases). The checker provisions
the scenario, drives the DELIVERED /app/configure.sh, /app/fixperms.sh and
/app/mapper.py, and asserts the competency outcomes. Returns 0 iff all pass.
"""
import importlib
import json
import os
import subprocess
import sys

CONFIGURE = "/app/configure.sh"
FIXPERMS = "/app/fixperms.sh"
MEMBER = "meridian"
OUTSIDER = "hopper"


def run(cmd):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT)
    return r.returncode, (r.stdout or b"").decode(errors="replace")


def asuser(user, cmd):
    return run("runuser -u %s -- %s" % (user, cmd))


def check_deny(share, fails, label):
    code, out = asuser(OUTSIDER, "cd %s" % share)
    if code == 0:
        fails.append("%s: outsider cd succeeded" % label)
    code, out = asuser(OUTSIDER, "cat %s 2>/dev/null" % share)
    if code == 0 and out.strip():
        fails.append("%s: outsider read from share (%r)" % (label, out))
    mode = split_oct(os.stat(share).st_mode & 0o777)
    if mode != "770":
        fails.append("%s: shared dir mode not groups-only (got %s)" % (label, mode))


def split_oct(m):
    return oct(m)[2:]


def check_acl(share, group, fails, label):
    code, out = run("getfacl -c %s/bin 2>/dev/null" % share)
    if "default:mask::rwx" not in out:
        fails.append("%s: ACL default mask does not preserve execute" % label)
    if "default:group:%s:rwx" % group not in out:
        fails.append("%s: ACL default group lacks rwx" % label)


def check_fixperms(sd, scripts, fails, label):
    for name in scripts:
        p = os.path.join(sd, name)
        mode = split_oct(os.stat(p).st_mode & 0o777)
        if mode != "755":
            fails.append("%s: %s not 0755 (got %s)" % (label, name, mode))
        if not os.access(p, os.X_OK):
            fails.append("%s: %s not executable" % (label, name))
        code, _ = run("head -n1 %s >/dev/null 2>&1" % p)
        if code != 0:
            fails.append("%s: %s not readable after fix" % (label, name))


def normalize_from_app(items):
    if "/app" not in sys.path:
        sys.path.insert(0, "/app")
    from mapper import normalize  # delivered /app/mapper.py
    return normalize(items)


def run_mapper_extra(ex_path, fails, label=""):
    data = json.load(open(ex_path))
    for c in data["cases"]:
        got = normalize_from_app(c["input"])
        if got != c["expected"]:
            fails.append("%s normalize() mismatch got=%s want=%s" % (label, got, c["expected"]))


def run_case(scenario, case_dir, fails):
    kind = scenario.get("kind", "variant")
    group = scenario.get("group", "anchorline")
    scripts = scenario.get("scripts", {})

    if kind == "file":
        fpath = scenario["file"]
        content = b"keepme-line\n"
        with open(fpath, "wb") as f:
            f.write(content)
        code, out = run("%s %s" % (CONFIGURE, fpath))
        if code == 0:
            fails.append("configure.sh accepted a regular-file path")
        with open(fpath, "rb") as f:
            if f.read() != content:
                fails.append("configure.sh modified a file path")
        sd = scenario["script_dir"]
        os.makedirs(sd, exist_ok=True)
        for name, mode in scripts.items():
            p = os.path.join(sd, name)
            with open(p, "w") as fp:
                fp.write("#!/bin/bash\necho daemon-ok\n")
            os.chmod(p, int(mode, 8))
        code, out = run("%s %s" % (FIXPERMS, sd))
        if code != 0:
            fails.append("fixperms.sh failed: %s" % out)
        check_fixperms(sd, scripts, fails, kind)
        return

    share = scenario["dir"]
    pre = scenario.get("precreate", True)
    if pre:
        os.makedirs(os.path.join(share, "bin"), exist_ok=True)
        os.chmod(share, 0o777)
        os.chmod(os.path.join(share, "bin"), 0o777)
        for name, mode in scripts.items():
            p = os.path.join(share, "bin", name)
            with open(p, "w") as fp:
                fp.write("#!/bin/bash\necho %s\n" % name.split(".")[0])
            os.chmod(p, int(mode, 8))
        with open(os.path.join(share, "bin", "note.txt"), "w") as fp:
            fp.write("do-not-touch\n")
        os.chmod(os.path.join(share, "bin", "note.txt"), 0o644)

    code, out = run("%s %s %s" % (CONFIGURE, share, group))
    if code != 0:
        fails.append("configure.sh failed on %s: %s" % (kind, out))
    check_deny(share, fails, kind)
    if os.path.isdir(os.path.join(share, "bin")):
        check_acl(share, group, fails, kind)

    code, out = run("%s %s/bin" % (FIXPERMS, share))
    if code != 0:
        fails.append("fixperms.sh failed on %s: %s" % (kind, out))
    if scripts:
        check_fixperms(os.path.join(share, "bin"), scripts, fails, kind)
    if pre:
        with open(os.path.join(share, "bin", "note.txt")) as fp:
            if fp.read().strip() != "do-not-touch":
                fails.append("%s: non-script file altered" % kind)
    # end-to-end: a group member actually executes a fixed script
    first = next(iter(scripts)) if scripts else None
    if first:
        code, out = asuser(MEMBER, "%s/bin/%s" % (share, first))
        if code != 0:
            fails.append("%s: member could not exec %s (%s)" % (kind, first, out.strip()))


def main():
    case_dir = sys.argv[1]
    scenario = json.load(
        open(os.path.join(case_dir, "input", "scenario.json")))
    fails = []
    run_case(scenario, case_dir, fails)
    run_mapper_extra(os.path.join(case_dir, "input", "examples_extra.json"), fails, "case")
    name = os.path.basename(case_dir)
    if fails:
        for f in fails:
            print("   FAIL[%s]: %s" % (name, f))
        return 1
    print("CASE %s OK" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())