#!/usr/bin/env python3
"""dust-tape oracle: the /app/triage.py deliverable (header-based classifier)."""
import json
import os
import struct
import sys

AOUT = {0x0107: "shared-text", 0x0108: "pure-text",
        0x0109: "separate-i&d", 0x010B: "overlay"}
ELF_MACH = {3: "x86", 62: "x86_64", 40: "arm", 183: "aarch64", 8: "mips",
            20: "powerpc", 21: "powerpc64", 243: "riscv", 18: "sparc",
            5: "m68k", 50: "ia64"}
KEYS = ["format", "arch", "host_executable", "magic_hex", "variant",
        "tsize", "dsize", "bsize", "symsize", "entry", "trsize", "drsize",
        "mem_image", "note"]


def blank():
    return {"format": "unknown", "arch": "unknown", "host_executable": False,
            "magic_hex": None, "variant": None, "tsize": None, "dsize": None,
            "bsize": None, "symsize": None, "entry": None, "trsize": None,
            "drsize": None, "mem_image": None, "note": ""}


def classify(blob):
    info = blank()
    if blob[:4] == b"\x7fELF":
        if len(blob) < 20:
            info["format"] = "elf-truncated"
            return info
        ei_class, ei_data = blob[4], blob[5]
        info["format"] = {1: "elf-32", 2: "elf-64"}.get(ei_class, "elf-?")
        if ei_data == 1:
            machine = struct.unpack_from("<H", blob, 18)[0]
        elif ei_data == 2:
            machine = struct.unpack_from(">H", blob, 18)[0]
        else:
            machine = struct.unpack_from("<H", blob, 18)[0]
        info["arch"] = ELF_MACH.get(machine, "unknown-elf-machine-%d" % machine)
        info["host_executable"] = info["arch"] == "x86_64"
        return info
    if blob[:2] == b"MZ":
        info["format"] = "pe"
        info["arch"] = "x86-family"
        return info
    if len(blob) >= 2:
        word = struct.unpack_from("<H", blob, 0)[0]
        if word in AOUT:
            info["format"] = "a.out"
            info["arch"] = "pdp11"
            info["host_executable"] = False
            info["magic_hex"] = "0x%04x" % word
            info["variant"] = AOUT[word]
            info["note"] = ("PDP-11 a.out: machine code for the old 16-bit "
                            "PDP-11 architecture, not runnable on this host")
            names = ["tsize", "dsize", "bsize", "symsize", "entry",
                     "trsize", "drsize"]
            vals = []
            for i, name in enumerate(names):
                off = 2 + 2 * i
                if len(blob) >= off + 2:
                    v = struct.unpack_from("<H", blob, off)[0]
                    vals.append(v)
                    info[name] = v
                else:
                    vals.append(None)
            if all(v is not None for v in vals[:3]):
                info["mem_image"] = vals[0] + vals[1] + vals[2]
            return info
    if len(blob) >= 8:
        printable = sum(1 for c in blob
                        if 0x20 <= c <= 0x7e or c in (0x0A, 0x09))
        if printable > 0.9 * len(blob):
            info["format"] = "text"
    return info


def main():
    path = sys.argv[1]
    with open(path, "rb") as fh:
        blob = fh.read()
    info = classify(blob)
    out = {k: info[k] for k in KEYS}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
