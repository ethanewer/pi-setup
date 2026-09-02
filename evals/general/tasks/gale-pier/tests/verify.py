#!/usr/bin/env python3
"""Gale Pier verifier (executes-deliverable).

Executes every deliverable with literal /app paths:
  1. /app/build-kernel.sh  -- must rebuild a bootable bzImage from clean sources
  2. /app/provision.sh     -- run TWICE; must stay idempotent (exactly one of
                              each top-level resource: users bilge/halyard,
                              group spinnaker, busybox core binary)
  3. /app/boot-qemu.sh     -- must boot bzImage+rootfs under QEMU and capture
                              the operational marker in /app/boot-serial.log
  4. /app/legacy/emulate.sh -- main fixture plus hidden binaries; compares the
                              printed arithmetic output against THIS script's
                              own decoder of the documented Pyxie machine.

Reward is written to /logs/verifier/reward.txt (1 = all checks pass).
"""
import hashlib
import os
import struct
import subprocess
import sys

REWARD_FILE = "/logs/verifier/reward.txt"
BUSYBOX_SHA = "dbac288c29ba568459550a2da9e7ae0ded6b1fc728ee9fad3044c44e62d6ac14"
MARKER = "GALE-PIER-GUEST-OPERATIONAL"

failures = []
notes = []


def check(name, ok, detail=""):
    if ok:
        notes.append("ok    %-28s %s" % (name, detail))
    else:
        failures.append("FAIL  %-28s %s" % (name, detail))
        print("FAIL  %-28s %s" % (name, detail), file=sys.stderr)


def run(args):
    p = subprocess.run(args, stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE)
    return p.returncode, p.stderr.decode(errors="replace")


def w32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


# Independent decoder of the Pyxie machine (documented in instruction.md).
def decode_program(path):
    with open(path, "rb") as fh:
        data = fh.read()
    regs = [0] * 16
    out = []
    n = len(data) // 8
    for i in range(n):
        rec = data[i * 8:(i + 1) * 8]
        op = rec[0]
        rd = rec[1] & 0x0F
        ra = rec[2] & 0x0F
        rb = rec[3] & 0x0F
        imm = struct.unpack("<i", rec[4:8])[0]
        if op == 0xFF:                    # HALT: stop, ignore the rest
            break
        if op == 0x11:                    # LD
            regs[rd] = imm
        elif op == 0x21:                  # ADD
            regs[rd] = w32(regs[ra] + regs[rb])
        elif op == 0x22:                  # SUB
            regs[rd] = w32(regs[ra] - regs[rb])
        elif op == 0x23:                  # MUL
            regs[rd] = w32(regs[ra] * regs[rb])
        elif op == 0x30:                  # PRT
            out.append(regs[ra])
        # any other opcode byte: the instruction is ignored, execution continues
    return out


def expected_text(vals):
    return "".join("%d\n" % v for v in vals)


def read_text(path):
    with open(path, "r") as fh:
        return fh.read()


def count_lines(path, prefix):
    if not os.path.isfile(path):
        return 0
    with open(path, "r") as fh:
        return sum(1 for ln in fh if ln.startswith(prefix))


def main():
    # ------------------------------------------------------------ presence --
    required = [
        "/app/build-kernel.sh",
        "/app/provision.sh",
        "/app/boot-qemu.sh",
        "/app/kernel/bzImage",
        "/app/rootfs/bin/busybox",
        "/app/boot-serial.log",
        "/app/legacy/emulate.sh",
        "/app/legacy/output.txt",
    ]
    for p in required:
        check("present " + p, os.path.exists(p), "")
    for p in ("/app/build-kernel.sh", "/app/provision.sh",
              "/app/boot-qemu.sh", "/app/legacy/emulate.sh"):
        check("executable " + p, os.path.isfile(p) and os.access(p, os.X_OK), "")
    if failures:
        check("early-exit (unverifiable base)", False,
              "deliverables missing -> reward 0")
        write_reward(0)
        sys.exit(0)

    # ------------------------------------------------ core OS files + login --
    h = hashlib.sha256(open("/app/rootfs/bin/busybox", "rb").read()).hexdigest()
    check("busybox content hash recognized", h == BUSYBOX_SHA,
          h[:16] + "...")

    bb = "/app/rootfs/bin/busybox"

    def link_target(link_path):
        # Resolve a symlink the way the GUEST sees it: treat the rootfs's "//"
        # as the real root, so a link to /bin/busybox means the rootfs copy
        # (host-side realpath would follow the host's usrmerge /usr/bin).
        d = os.path.dirname(link_path)
        t = os.readlink(link_path)
        if os.path.isabs(t):
            t = os.path.join("/app/rootfs", t.lstrip("/"))
        else:
            t = os.path.join(d, t)
        return os.path.normpath(t)

    for tool in ("sh", "ls"):
        check("symlink /app/rootfs/bin/%s -> busybox" % tool,
              os.path.islink("/app/rootfs/bin/" + tool)
              and link_target("/app/rootfs/bin/" + tool) == bb,
              "target=%s" % link_target("/app/rootfs/bin/" + tool) if os.path.islink("/app/rootfs/bin/" + tool) else "not a link")

    pw = "/app/rootfs/etc/passwd"
    gr = "/app/rootfs/etc/group"
    check("account bilge present", count_lines(pw, "bilge:") == 1, "")
    check("account halyard present", count_lines(pw, "halyard:") == 1, "")
    check("group spinnaker present", count_lines(gr, "spinnaker:") == 1, "")
    with open(gr, "r") as fh:
        grp = next((ln for ln in fh if ln.startswith("spinnaker:")), "")
    check("spinnaker members bilge,halyard",
          "bilge" in grp.split(":")[-1] and "halyard" in grp.split(":")[-1],
          grp.strip())

    # ------------------------------------------------------------- re-provision
    rc, err = run(["/app/provision.sh"])
    check("provision.sh run 1", rc == 0, err[-200:] if rc else "")
    rc, err = run(["/app/provision.sh"])
    check("provision.sh run 2 (idempotency)", rc == 0, err[-200:] if rc else "")

    check("exactly one bilge entry after 2 re-runs",
          count_lines(pw, "bilge:") == 1, "count=%d" % count_lines(pw, "bilge:"))
    check("exactly one halyard entry after 2 re-runs",
          count_lines(pw, "halyard:") == 1, "count=%d" % count_lines(pw, "halyard:"))
    check("exactly one spinnaker entry after 2 re-runs",
          count_lines(gr, "spinnaker:") == 1, "count=%d" % count_lines(gr, "spinnaker:"))
    check("exactly one busybox binary after 2 re-runs",
          os.path.isfile(bb), "single file at %s" % bb)
    h2 = hashlib.sha256(open(bb, "rb").read()).hexdigest()
    check("busybox hash intact after re-provision", h2 == BUSYBOX_SHA, h2[:16])

    # ------------------------------------------------------------ rebuild kernel
    rc, err = run(["/app/build-kernel.sh"])
    check("build-kernel.sh rebuilds", rc == 0, err[-300:] if rc else "")
    bz = "/app/kernel/bzImage"
    size = os.path.getsize(bz) if os.path.isfile(bz) else 0
    check("bzImage exists and non-trivial", os.path.isfile(bz) and size > 5_000_000,
          "size=%d" % size)

    # --------------------------------------------------------------- qemu boot
    rc, err = run(["/app/boot-qemu.sh"])
    check("boot-qemu.sh run", rc == 0, err[-300:] if rc else "")
    log = read_text("/app/boot-serial.log") if os.path.isfile("/app/boot-serial.log") else ""
    check("serial log has operational marker", MARKER in log, "")
    check("serial log shows an operational shell", "built-in shell" in log, "")

    # ---------------------------------------------------------------- legacy --
    rc, err = run(["/app/legacy/emulate.sh"])
    check("emulate.sh (main fixture)", rc == 0, err[-200:] if rc else "")
    got = read_text("/app/legacy/output.txt")
    want = expected_text(decode_program("/app/legacy/legacy.bin"))
    check("main output matches verifier decode", got == want,
          "got=%r want=%r" % (got.strip().split(), want.strip().split()))

    hid_dir = "/tests/hidden"
    cases = sorted(fn for fn in os.listdir(hid_dir) if fn.endswith(".bin")) \
        if os.path.isdir(hid_dir) else []
    if not cases:
        check("hidden cases present", False, "no /tests/hidden/*.bin")
    for fn in cases:
        case = os.path.join(hid_dir, fn)
        tmp = "/tmp/verify_" + fn.replace(".bin", ".txt")
        rc, err = run(["/app/legacy/emulate.sh", case, tmp])
        check("emulate.sh hidden %s" % fn, rc == 0, err[-200:] if rc else "")
        got = read_text(tmp)
        want = expected_text(decode_program(case))
        check("hidden %s output matches" % fn, got == want,
              "got=%r want=%r" % (got.strip().split(), want.strip().split()))

    # ------------------------------------------------------------------ done --
    all_ok = not failures
    write_reward(1 if all_ok else 0)
    print("VERIFIER: %d failures, reward=%d" % (len(failures), 1 if all_ok else 0),
          file=sys.stderr)


def write_reward(v):
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as fh:
        fh.write(str(v) + "\n")


if __name__ == "__main__":
    main()