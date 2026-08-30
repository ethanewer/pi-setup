#!/usr/bin/env bash
# Oracle for arid-jetty: writes the real /app/solve.py that implements every
# deliverable (wasm-probe driver, mutable closures/higher-order helpers, a value
# hash consistent with equality, the parallel work that imports the sequential
# iteration constant, and the canonical Vimscript emitter), then RUNS it to
# produce /app/answer.json and /app/recreate.vim. Never reads /tests.
set -eu

cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Arid Jetty polyglot / low-level harness.

Produces /app/answer.json and /app/recreate.vim. Implements:
  1. WebAssembly instantiator that calls the exported probe() and reads the byte
     at the returned offset in the module's linear memory.
  2. Mutable higher-order closures (shared-state counter), currying, and mutual
     recursion, plus a self-checking probe.
  3. A value type whose __hash__ is consistent with its __eq__.
  4. A parallel work routine whose cardinality is the sequential iteration
     constant imported from compute_seq (never re-stated inline).
  5. A canonical Vimscript file recording the tab/window/buffer topology.
"""
import json
import os
import subprocess
import sys

APP = "/app"
DATADIR = os.path.join(APP, "data")
RUNDIR = os.path.join(APP, "run")
if DATADIR not in sys.path:
    sys.path.insert(0, DATADIR)
sys.setrecursionlimit(100000)


# ---------------------------------------------------------------------------
# 1. wasm: exported function returning a memory offset
# ---------------------------------------------------------------------------
_NODE_WASM_PROBE = r'''
const fs = require('fs');
(async () => {
  const bin = process.argv[process.argv.length - 1];
  const data = fs.readFileSync(bin);
  if (!data || data[0] !== 0x00 || data[1] !== 0x61 ||
      data[2] !== 0x73 || data[3] !== 0x6d) {
    throw new Error('not-a-wasm-binary');
  }
  const { instance } = await WebAssembly.instantiate(data, {});
  const probe = instance.exports && instance.exports.probe;
  if (typeof probe !== 'function') throw new Error('missing-probe-export');
  const memory = instance.exports.memory;
  if (!memory || !(memory instanceof WebAssembly.Memory)) {
    throw new Error('missing-memory-export');
  }
  const offset = probe();
  if (typeof offset !== 'number' || !Number.isInteger(offset)) {
    throw new Error('probe-did-not-return-integer-offset');
  }
  const byte = new Uint8Array(memory.buffer)[offset];
  process.stdout.write(JSON.stringify([offset, byte]));
})().catch(e => { console.error('WASM:' + e.message); process.exit(1); });
'''

def wasm_probe(binary=None):
    """Instantiate the module and call probe(); return (offset, byte) where byte
    is the value in linear memory at the returned offset. Raise ValueError on a
    missing file, a non-wasm binary, or a module without the probe/memory export."""
    if binary is None:
        binary = os.path.join(DATADIR, "mem.wasm")
    if not os.path.exists(binary):
        raise ValueError("wasm binary not found: %s" % binary)
    p = subprocess.run(["node", "-e", _NODE_WASM_PROBE, binary],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise ValueError("wasm probe failed: " + p.stderr.strip())
    offset, byte = json.loads(p.stdout)
    return (int(offset), int(byte))


# ---------------------------------------------------------------------------
# 2. higher-order closures, currying, mutual recursion
# ---------------------------------------------------------------------------
def make_counter(start):
    """Return (inc, dec); both closures share one mutable cell seeded with start."""
    box = {"n": int(start)}

    def inc(by=1):
        box["n"] += by
        return box["n"]

    def dec(by=1):
        box["n"] -= by
        return box["n"]

    return inc, dec


def curry_add(a):
    """Curried adder: curry_add(a)(b) == a+b; curry_add(a)(b, c) == a+b+c."""
    def adder(*args):
        return a + sum(args)
    return adder


def mutual_even(n):
    n = -n if n < 0 else n
    return True if n == 0 else mutual_odd(n - 1)


def mutual_odd(n):
    n = -n if n < 0 else n
    return False if n == 0 else mutual_even(n - 1)


def closure_probe():
    """Snapshot in the exact shape recorded in answer.json."""
    inc, dec = make_counter(10)
    seq = [inc(2), inc(1), dec(20), inc(7)]      # [12, 13, -7, 0]
    return {
        "seq": seq,
        "curry": curry_add(4)(5),                # 9
        "even12": mutual_even(12),               # True
        "odd13": mutual_odd(13),                 # True
    }


# ---------------------------------------------------------------------------
# 3. object hash consistent with equality
# ---------------------------------------------------------------------------
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def __eq__(self, other):
        if not isinstance(other, Point):
            return NotImplemented
        return (self.x, self.y) == (other.x, other.y)

    def __hash__(self):
        return hash((self.x, self.y))


def hash_signature():
    a = Point(2, 3)
    b = Point(2, 3)
    c = Point(2, 4)
    return {
        "equal": a == b,
        "equal_same_hash": hash(a) == hash(b),
        "self_in_set": len({a, b, Point(2, 3)}) == 1,
        "unequal_diff_hash": (a != c) and (hash(a) != hash(c)),
    }


# ---------------------------------------------------------------------------
# 4. sequential iteration constant consumed by import (never inline)
# ---------------------------------------------------------------------------
def _iterations():
    import compute_seq
    return compute_seq.ITERATIONS


def get_iterations():
    return _iterations()


def compute_parallel():
    """Parallel work whose cardinality tracks the imported sequential constant."""
    iters = _iterations()
    return [i * 2 for i in range(iters)]


# ---------------------------------------------------------------------------
# 5. canonical Vimscript layout emitter
# ---------------------------------------------------------------------------
def emit_vimscript(path="/app/recreate.vim"):
    a = os.path.join(RUNDIR, "alpha.txt")
    b = os.path.join(RUNDIR, "beta.txt")
    g = os.path.join(RUNDIR, "gamma.txt")
    script = (
        "set nocompatible\n"
        "silent edit %s\n"
        "silent split %s\n"
        "silent tabnew %s\n"
    ) % (a, b, g)
    with open(path, "w") as fh:
        fh.write(script)
    return path


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------
def main():
    woff, wbyte = wasm_probe()
    answer = {
        "wasm_offset": woff,
        "wasm_byte": wbyte,
        "closure": closure_probe(),
        "iterations": get_iterations(),
        "parallel_len": len(compute_parallel()),
        "hash_consistent": all(hash_signature().values()),
        "vim_script": emit_vimscript(),
    }
    with open("/app/answer.json", "w") as fh:
        json.dump(answer, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print("answer.json written; wasm offset=%d byte=%d parallel_len=%d" %
          (woff, wbyte, len(compute_parallel())))


if __name__ == "__main__":
    main()
PY

chmod +x /app/solve.py
python3 /app/solve.py
echo "oracle: answer.json + recreate.vim produced"