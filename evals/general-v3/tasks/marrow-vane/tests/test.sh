#!/bin/bash
# Verifier for marrow-vane: ENFORCES no-modify on the shipped emulator and
# legacy image, EXECUTES the deliverable runner (/app/legacy/emulate.sh) on the
# shipped image and on every hidden image in /tests/hidden, and compares the
# captured serial output against an INDEPENDENT Corvid-8 reference
# implementation of the documented ISA. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of shipped fixtures (instruction forbids modification).
WANT_EMU_SHA="0700c0bb3a07ed2f60b63878305459beab991f5e977b487a91ebdee4247d7bf8"
WANT_ROM_SHA="6c4e8edaa202dcc13dc635111c4ea0f23cf41da123465693125a9e2f3b4c49aa"

no_modify_broken=0
if [ ! -f /app/bench/corvid-emu ]; then
    echo "no-modify: /app/bench/corvid-emu missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/bench/corvid-emu | awk '{print $1}')"
    if [ "$actual" != "$WANT_EMU_SHA" ]; then
        echo "no-modify: /app/bench/corvid-emu was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -f /app/legacy/course_fix.bin ]; then
    echo "no-modify: /app/legacy/course_fix.bin missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/legacy/course_fix.bin | awk '{print $1}')"
    if [ "$actual" != "$WANT_ROM_SHA" ]; then
        echo "no-modify: /app/legacy/course_fix.bin was modified" >&2
        no_modify_broken=1
    fi
fi

# The runner must drive the installed emulator host, not reimplement it.
if [ -f /app/legacy/emulate.sh ] && ! grep -q "/app/bench/corvid-emu" /app/legacy/emulate.sh; then
    echo "contract: emulate.sh does not invoke /app/bench/corvid-emu" >&2
    no_modify_broken=1
fi

python3 - "$no_modify_broken" <<'PY'
import json
import os
import struct
import subprocess
import sys
import tempfile

no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("emulator/image tampered or runner does not drive the emulator host")


def reference_emulate(rom: bytes) -> str:
    """Independent Corvid-8 reference per /app/docs/corvid-datasheet.md."""
    MEM = bytearray(65536)
    load = 512
    img_end = load + len(rom)
    MEM[load:img_end] = rom
    pc = load
    a = 0
    out = []

    def rd16(x):
        x %= 65536
        return MEM[x] | (MEM[(x + 1) % 65536] << 8)

    while pc < img_end and pc < 65536:
        op = MEM[pc]
        if op == 0x00:
            pc += 1
        elif op == 0xFF:
            break
        elif op == 0x30:
            out.append("%d\n" % a)
            pc += 1
        elif op in (0x10, 0x11, 0x12, 0x13, 0x20, 0x21):
            if pc + 3 > img_end:
                break
            imm = rd16(pc + 1)
            if op == 0x10:
                a = imm
            elif op == 0x11:
                a = (a + imm) & 0xFFFF
            elif op == 0x12:
                a = (a - imm) & 0xFFFF
            elif op == 0x13:
                a = (a * imm) & 0xFFFF
            elif op == 0x20:
                MEM[imm % 65536] = a & 0xFF
                MEM[(imm + 1) % 65536] = (a >> 8) & 0xFF
            else:
                a = rd16(imm)
            pc += 3
        else:
            pc += 1
    return "".join(out)


def run_runner(rom, out_path):
    r = subprocess.run(["/app/legacy/emulate.sh", rom, out_path],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return None
    if not os.path.isfile(out_path):
        return None
    with open(out_path, "rb") as fh:
        return fh.read()


PROFILE = "/app/bench/coursefix.profile.json"

if not (os.path.isfile("/app/legacy/emulate.sh")
        and os.access("/app/legacy/emulate.sh", os.X_OK)):
    failures.append("missing or non-executable /app/legacy/emulate.sh")
elif not os.path.isfile(PROFILE):
    failures.append("missing /app/bench/coursefix.profile.json")
else:
    try:
        prof = json.load(open(PROFILE))
        if not isinstance(prof, dict) or not all(
            isinstance(prof.get(k), int) for k in
            ("memory_kib", "load_address", "entry", "serial_out_address")
        ):
            failures.append("profile lacks the four integer keys")
    except Exception:
        failures.append("profile is not valid JSON")
        prof = None

    if not failures:
        # --- shipped image ---
        with open("/app/legacy/course_fix.bin", "rb") as fh:
            want = reference_emulate(fh.read()).encode()
        work = tempfile.mkdtemp(prefix="mv_ship_")
        out = os.path.join(work, "out.txt")
        got = run_runner("/app/legacy/course_fix.bin", out)
        if got is None:
            failures.append("runner failed on the shipped image")
        elif got != want:
            failures.append("shipped image output mismatch")
        if not os.path.isfile("/app/legacy/output.txt"):
            failures.append("missing /app/legacy/output.txt")
        else:
            with open("/app/legacy/output.txt", "rb") as fh:
                if fh.read() != want:
                    failures.append("/app/legacy/output.txt mismatch")

        # --- hidden images ---
        hidden_dir = "/tests/hidden"
        if os.path.isdir(hidden_dir):
            cases = sorted(os.listdir(hidden_dir))
            if not cases:
                failures.append("no hidden cases present")
            for c in cases:
                rom = os.path.join(hidden_dir, c, "rom.bin")
                if not os.path.isfile(rom):
                    failures.append("hidden '%s' malformed" % c)
                    continue
                with open(rom, "rb") as fh:
                    want = reference_emulate(fh.read()).encode()
                work = tempfile.mkdtemp(prefix="mv_hid_")
                out = os.path.join(work, "out.txt")
                got = run_runner(rom, out)
                if got is None:
                    failures.append("hidden case '%s': runner failed" % c)
                elif got != want:
                    failures.append("hidden case '%s': output mismatch" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
