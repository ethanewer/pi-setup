#!/usr/bin/env bash
# Oracle for umber-engine: authors the three deliverables by doing the work,
# then self-checks them before finishing.
set -euo pipefail
cd /app

cat > /app/seq.py <<'PY'
import sys

def seq(n):
    if n < 0 or n > 100:
        return None
    if n < 3:
        return 1
    p = [1, 1, 1]
    for k in range(3, n + 1):
        p.append(p[k - 2] + p[k - 3])
    return p[n]

def main():
    if len(sys.argv) != 2:
        sys.stderr.write("ERR\n")
        sys.exit(2)
    try:
        n = int(sys.argv[1])
    except ValueError:
        sys.stderr.write("ERR\n")
        sys.exit(2)
    v = seq(n)
    if v is None:
        sys.stderr.write("ERR\n")
        sys.exit(2)
    print(v)

main()
PY

cat > /app/seq.rs <<'RS'
use std::env;
use std::process;

fn seq(n: u64) -> Option<u64> {
    if n > 100 {
        return None;
    }
    if n < 3 {
        return Some(1);
    }
    let mut p: Vec<u64> = vec![1, 1, 1];
    for k in 3..=n {
        let v = p[(k - 2) as usize] + p[(k - 3) as usize];
        p.push(v);
    }
    Some(p[n as usize])
}

fn main() {
    let mut args = env::args();
    args.next();
    let raw = match args.next() {
        Some(x) => x,
        None => {
            eprintln!("ERR");
            process::exit(2);
        }
    };
    let n: u64 = match raw.trim().parse() {
        Ok(v) => v,
        Err(_) => {
            eprintln!("ERR");
            process::exit(2);
        }
    };
    match seq(n) {
        Some(v) => println!("{}", v),
        None => {
            eprintln!("ERR");
            process::exit(2);
        }
    }
}
RS

cat > /app/wasm.c <<'C'
unsigned char buffer[256];

void boot(void) {
    int i;
    for (i = 0; i < 256; i++) {
        buffer[i] = (unsigned char)((i * 13 + 7) & 0xFF);
    }
}

int producer(int seed) {
    return (seed * 31 + 7) % 240;
}

int consumer(int offset) {
    int s = 0;
    int i;
    for (i = 0; i < 16; i++) {
        s += buffer[offset + i];
    }
    return s;
}
C

chmod 644 /app/seq.py /app/seq.rs /app/wasm.c

# ---- self-check (mirrors the verifier, but never reads /tests) ----
python3 - <<'PY'
import subprocess, sys, os, tempfile

def run(c):
    r = subprocess.run(c, capture_output=True, text=True)
    return r.returncode, r.stdout.strip()

def seq(n):
    if n < 0 or n > 100:
        return None
    p = [1, 1, 1]
    for k in range(3, n + 1):
        p.append(p[k - 2] + p[k - 3])
    return p[n]

# sequence, both runtimes
subprocess.run(["rustc", "-O", "/app/seq.rs", "-o", "/tmp/seq_rs_self"], check=True)
for n in [0, 1, 2, 3, 10, 40, 88, 100]:
    rc_py, out_py = run([sys.executable, "/app/seq.py", str(n)])
    rc_rs, out_rs = run(["/tmp/seq_rs_self", str(n)])
    assert rc_py == 0 and out_py == str(seq(n)), (n, out_py)
    assert rc_rs == 0 and out_rs == out_py, (n, out_rs)

# wasm: compile and run a quick probe
subprocess.run(["clang", "--target=wasm32-unknown-unknown", "-O2", "-nostdlib",
                "-Wl,--no-entry", "-Wl,--export-all", "-o", "/tmp/wc.wasm", "/app/wasm.c"],
               check=True)
import wasmtime
from wasmtime import Store, Module, Instance
st = Store()
mod = Module.from_file(st.engine, "/tmp/wc.wasm")
ins = Instance(st, mod, [])
x = ins.exports(st)
boot, producer, consumer = x["boot"], x["producer"], x["consumer"]
memory, base = x["memory"], x["buffer"].value(st)
boot(st)
for seed in [0, 7, 199]:
    off = int(producer(st, seed))
    got = int(consumer(st, off))
    data = memory.read(st, base + off, base + off + 16)
    assert len(data) == 16, seed
    assert list(data) == [((off + k) * 13 + 7) & 0xFF for k in range(16)], seed
    assert got == sum(data), seed

print("oracle self-check OK")
PY

rm -f /tmp/seq_rs_self /tmp/wc.wasm
echo "UMBER-ENGINE ORACLE DONE"