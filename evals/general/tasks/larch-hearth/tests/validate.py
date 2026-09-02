#!/usr/bin/env python3
"""larch-hearth verifier helper.

Validates the declared deliverables (task.toml metadata.deliverables):

    /app/run.sh      (checked separately by tests/test.sh)
    /app/guest.iso   (rebuilt by /app/run.sh, validated here)
    /app/serial.log  (captured by /app/run.sh, validated here)

Against a scenario JSON: the captured serial.log markers, the host-fs
guest.prog.exit, and the rebuilt guest.iso (a valid ISO9660 whose
toolkit/manifest.txt first line equals the scenario payload).

Usage: validate.py OUTDIR SCENARIO_JSON
Exit 0 + PASS on success; exit 1 + FAIL otherwise.
"""
import json
import os
import subprocess
import sys


def fail(msg):
    print(f"FAIL: {msg}")
    return 1


def check(cond, errs, name):
    if not cond:
        errs.append(name)


def main():
    outdir, scen_path = sys.argv[1], sys.argv[2]
    # Deliverable output files (declared in task.toml): /app/guest.iso and
    # /app/serial.log are on disk at OUTDIR/serial.log and OUTDIR/guest.iso
    # since run.sh writes them into OUTDIR (default /app).
    scen = json.load(open(scen_path))
    es = scen["exit_status"]
    payload = scen["payload"]
    luser = scen.get("login_user", "root")

    errs = []

    # ---- serial.log -----------------------------------------------------
    slog = os.path.join(outdir, "serial.log")
    if not os.path.isfile(slog):
        return fail(f"no {outdir}/serial.log")
    txt = open(slog, "rb").read().decode("utf-8", "ignore")

    req = [
        "LARCH_BOOT_OK",
        "LARCH_CDROM_MOUNT_OK",
        "TOOL_RAN_OK",
        "LARCH_HOSTROOT_MOUNT_OK",
        "LARCH_CDTOOL_COPIED",
        "LARCH_COMPILE_OK",
        "LARCH_READY_FOR_LOGIN",
        "login:",
        "LARCH_AUTH_OK",
    ]
    for m in req:
        check(m in txt, errs, f"serial:{m}")

    # profile is in 1..255
    check(str(es) in txt, errs, "serial:exit_status_substring")
    check(f"ASM_EXIT_STATUS={es}" in txt, errs, "serial:ASM_EXIT_STATUS")
    check(payload in txt, errs, "serial:payload")
    # login user's account must be accepted (no password)
    check(luser in txt, errs, "serial:login_user")

    # ---- host-fs guest write (syscall file-io via 9p) --------------------
    gpe = os.path.join(outdir, "guest.prog.exit")
    if not os.path.isfile(gpe):
        return fail(f"no {outdir}/guest.prog.exit (guest host-fs write missing)")
    v = open(gpe).read().strip()
    check(v == str(es), errs, "guest.prog.exit")

    # ---- guest.iso: valid ISO whose manifest first line == payload -------
    iso = os.path.join(outdir, "guest.iso")
    if not os.path.isfile(iso):
        return fail(f"no {outdir}/guest.iso")
    check(is_iso9660(iso), errs, "iso:9660")
    manifest = extract_iso_file(iso, "/toolkit/manifest.txt")
    if manifest is None:
        check(False, errs, "iso:manifest_extract")
    else:
        first = manifest.decode("utf-8", "ignore").strip()
        check(first == payload, errs, "iso:manifest_payload")

    if errs:
        print(f"FAIL: {errs}")
        return 1
    print("PASS")
    return 0


def is_iso9660(path):
    with open(path, "rb") as f:
        head = f.read(0x20000)  # 128 KiB — covers the PVD 'CD001' magic at 0x8001
    return b"CD001" in head


def extract_iso_file(iso, path):
    """Return bytes of a file inside the ISO (via xorriso) or None."""
    dst = "/tmp/larch_validate_x"
    subprocess.run(["rm", "-rf", dst])
    os.makedirs(dst)
    r = subprocess.run(
        ["xorriso", "-indev", iso, "-osirrox", "on", "-extract", "/toolkit", dst],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if r.returncode != 0:
        return None
    target = os.path.join(dst, "manifest.txt")
    if not os.path.isfile(target):
        return None
    return open(target, "rb").read()


if __name__ == "__main__":
    sys.exit(main())
