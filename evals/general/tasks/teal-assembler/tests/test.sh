#!/bin/bash
# Verifier for teal-assembler (executes-deliverable).
# Executes the /app/assemble.py deliverable on the visible source and on
# every hidden case under /tests/hidden, checking byte-exact machine code
# for valid programs and the required nonzero exit (with no output file)
# for each documented error case. Writes the numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import os
import subprocess
import sys

ASM = '/app/assemble.py'
BIN = '/app/program.bin'
SRC = '/app/program.src'
VIS_HEX = '1001072011300000ff'

problems = []


def assemble(src, out):
    r = subprocess.run(['python3', ASM, src, out],
                       capture_output=True, text=True)
    return r


def hexlify(path):
    with open(path, 'rb') as f:
        return f.read().hex()


# --- deliverable /app/program.bin must exist and be byte-exact for the
#     visible program. ---
if not os.path.isfile(BIN):
    problems.append('missing /app/program.bin')
else:
    got = hexlify(BIN)
    if got != VIS_HEX:
        problems.append('program.bin %r != visible %r' % (got, VIS_HEX))

if not os.path.isfile(ASM):
    problems.append('missing /app/assemble.py')

if os.path.isfile(ASM):
    # --- re-run the assembler on the visible source: must succeed + match ---
    r = assemble(SRC, '/tmp/vis.bin')
    if r.returncode != 0:
        problems.append('visible assemble exit %d: %s'
                        % (r.returncode, r.stderr[:300]))
    else:
        got = hexlify('/tmp/vis.bin')
        if got != VIS_HEX:
            problems.append('visible reassembly %r != %r' % (got, VIS_HEX))

    # --- hidden cases ---
    hd = '/tests/hidden'
    for name in sorted(os.listdir(hd)):
        if not name.endswith('.src'):
            continue
        base = name[:-4]
        src = os.path.join(hd, name)
        hex_file = os.path.join(hd, base + '.hex')
        r = assemble(src, '/tmp/h.out.bin')
        if os.path.isfile(hex_file):
            # valid program: must assemble to the exact expected bytes
            with open(hex_file) as f:
                expected = f.read().strip()
            if r.returncode != 0:
                problems.append('%s failed: %s'
                                % (name, r.stderr[:300]))
            else:
                got = hexlify('/tmp/h.out.bin')
                if got != expected:
                    problems.append('%s -> %r want %r' % (name, got, expected))
        else:
            # error case: must exit nonzero and not produce the output file
            if r.returncode == 0:
                problems.append('%s expected an error but exited 0' % name)
            else:
                if not r.stderr.strip():
                    problems.append('%s errored but printed no diagnostic' % name)
                if os.path.exists('/tmp/h.out.bin'):
                    problems.append('%s wrote output despite error' % name)

if problems:
    for p in problems:
        print('FAIL:', p)
    sys.exit(1)

print('ALL_OK')
PY
then reward=1
fi

echo "$reward" > /logs/verifier/reward.txt