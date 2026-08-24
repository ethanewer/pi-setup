"""Regression test suite for the OCaml/C RLE round-trip project.

Run:  python3 -m pytest /app -q   (or pytest -q from /app)
Builds the runtime if needed, executes the round-trip, and checks the decoded
byte stream and its checksum.
"""
import subprocess
import sys
import os

ROOT = '/tmp' if False else '/app'
RUNS = [(3, 0x41), (160, 0x42), (2, 0x43), (130, 0x44),
        (1, 0x45), (255, 0x21), (1, 0x46)]


def expected():
    out = b''
    for n, v in RUNS:
        out += bytes([v]) * n
    return out


def checksum(blob):
    s = 0
    for x in blob:
        s = (s * 31 + x) & 0xFFFF
    return s & 0xFFFF


def _build_and_run():
    import os
    cwd = '/app'
    # ensure the spec stream exists
    if not os.path.isfile(os.path.join(cwd, 'rcode.dat')):
        subprocess.run(['ocaml', 'spec.ml'], cwd=cwd, check=True)
    # (re)compile the runtime
    subprocess.run(['gcc', '-std=c99', '-O2', 'runtime.c', '-o', 'runtime_t'],
                   cwd=cwd, check=True)
    res = subprocess.run(['./runtime_t'], cwd=cwd, capture_output=True, text=True)
    assert res.returncode == 0, res.stdout + res.stderr
    return res.stdout


def test_roundtrip_bytes():
    _round_and_run()
    with open('/app/out.dat', 'rb') as f:
        out = f.read()
    assert out == expected(), 'decoded byte stream differs from spec expansion'


def test_checksum():
    _round_and_run()
    with open('/app/out.dat', 'rb') as f:
        out = f.read()
    assert checksum(out) == checksum(expected())


def test_print_is_consistent():
    out = _round_and_run()
    assert 'CHECKSUM=' in out