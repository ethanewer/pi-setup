#!/usr/bin/env python3
"""validate.py <outdir> <scenario.json> for cinder-hearth.

Checks the captured session log for the full marker chain, extracts the
injected initramfs and inspects the init script (pseudo-fs mounts, serial
tty, login handoff), the unauthenticated /etc/passwd, and the embedded seed.
Exits 0 iff everything holds.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile


def fail(msg):
    print("VALIDATE FAIL: %s" % msg)
    sys.exit(1)


def main():
    out, scn_path = sys.argv[1], sys.argv[2]
    scn = json.load(open(scn_path))
    user = scn["user"]
    token = scn["token"]

    log_path = os.path.join(out, "session.log")
    initrd = os.path.join(out, "guest-initrd.cpio.gz")
    if not os.path.isfile(log_path) or not os.path.isfile(initrd):
        fail("missing session.log or guest-initrd.cpio.gz")

    log = open(log_path, "rb").read().decode("latin-1")

    markers = [
        "CINDER_BOOT_OK",
        "CINDER_PSEUDOFS_OK",
        "CINDER_SEED_TOKEN=%s" % token,
        "CINDER_SERIAL_TTY=ttyS0",
        "CINDER_READY_FOR_LOGIN",
        "login:",
        "CINDER_AUTH_OK",
    ]
    pos = 0
    for m in markers:
        idx = log.find(m, pos)
        if idx < 0:
            fail("marker %r missing (or out of order) in session.log" % m)
        pos = idx + len(m)

    # Extract the injected initramfs and inspect the init + accounts + seed.
    work = tempfile.mkdtemp(prefix="cinder_val_")
    try:
        tree = os.path.join(work, "tree")
        os.makedirs(tree)
        import gzip
        raw = gzip.open(initrd, "rb").read()
        r = subprocess.run("cpio -idm", shell=True, cwd=tree, input=raw,
                           capture_output=True)
        if r.returncode != 0 or not os.path.isfile(os.path.join(tree, "init")):
            fail("cannot unpack initramfs: %s" % r.stderr[-200:])

        init_path = os.path.join(tree, "init")
        if not os.path.isfile(init_path):
            fail("no /init in initramfs")
        init = open(init_path, errors="replace").read()

        for needle in ("proc", "sysfs", "devtmpfs", "ttyS0", "cttyhack", "login"):
            if needle not in init:
                fail("init script does not reference %r" % needle)
        if "CINDER_READY_FOR_LOGIN" not in init:
            fail("init does not print CINDER_READY_FOR_LOGIN")
        if "CINDER_SEED_TOKEN" not in init:
            fail("init does not print CINDER_SEED_TOKEN")

        passwd_path = os.path.join(tree, "etc", "passwd")
        if not os.path.isfile(passwd_path):
            fail("no /etc/passwd in initramfs")
        entries = {}
        for line in open(passwd_path):
            line = line.strip()
            if not line:
                continue
            fields = line.split(":")
            if len(fields) >= 7:
                entries[fields[0]] = fields
        if "root" not in entries:
            fail("no root account in /etc/passwd")
        if user not in entries:
            fail("scenario user %r missing from /etc/passwd" % user)
        for name in ("root", user):
            if entries[name][1] != "":
                fail("account %r has a non-empty password field (must be "
                     "unauthenticated)" % name)
            if not entries[name][6].endswith("sh"):
                fail("account %r has no usable shell" % name)

        token_path = os.path.join(tree, "seed", "token.txt")
        if not os.path.isfile(token_path):
            fail("no /seed/token.txt embedded in initramfs")
        content = open(token_path).read().strip()
        if content != token:
            fail("embedded token mismatch: %r != %r" % (content, token))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # The emulator must still be running as a background service.
    r = subprocess.run(["pgrep", "-f", "qemu-system"], capture_output=True)
    if r.returncode != 0:
        fail("qemu is not running after console_drive.py (background service "
             "requirement)")

    print("VALIDATE OK")
    sys.exit(0)


if __name__ == "__main__":
    main()
