#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Oracle solution for item-055-main: author the polyglot main.c (Python3 + C +
# C++) plus a matching main.rs, and a run_checks.py cross-engine harness that
# must print ALL PASS and write status.txt = PASS.
# ---------------------------------------------------------------------------

cat > /app/polyglot/main.c <<'CEOF'
#if 0
import sys
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
def py_main():
    args = sys.argv[1:]
    if len(args) != 1:
        sys.stderr.write("error: expected exactly one argument N (0..93)\n")
        sys.exit(1)
    s = args[0]
    if not s.isdigit() or int(s) > 93:
        sys.stderr.write("error: N must be a non-negative integer in 0..93\n")
        sys.exit(1)
    print(fib(int(s)))
py_main()
sys.exit(0)
#endif
#if 0
"""
#endif
#include <stdio.h>
#include <stdlib.h>
static unsigned long long fib(unsigned int n) {
    unsigned long long a = 0, b = 1, t;
    for (unsigned int i = 0; i < n; ++i) { t = a + b; a = b; b = t; }
    return a;
}
int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "error: expected exactly one argument N (0..93)\n");
        return 1;
    }
    const char *s = argv[1];
    for (const char *p = s; *p; ++p) {
        if (*p < '0' || *p > '9') {
            fprintf(stderr, "error: N must be a non-negative integer\n");
            return 1;
        }
    }
    unsigned long n = strtoul(s, 0, 10);
    if (n > 93) {
        fprintf(stderr, "error: N must be in 0..93\n");
        return 1;
    }
    printf("%llu\n", fib((unsigned)n));
    return 0;
}
#if 0
"""
#endif
CEOF

cat > /app/polyglot/main.rs <<'REOF'
// main.rs — byte-for-byte stdout match with the C-family engines.
fn fib(n: u64) -> u64 {
    let mut a: u64 = 0;
    let mut b: u64 = 1;
    for _ in 0..n {
        let t: u64 = a + b;
        a = b;
        b = t;
    }
    return a;
}

fn is_digits(s: &str) -> bool {
    if s.len() == 0 { return false; }
    for c in s.chars() {
        if c < '0' || c > '9' { return false; }
    }
    return true;
}

fn parse_num(s: &str) -> Option<u64> {
    if !is_digits(s) { return None; }
    let mut v: u64 = 0;
    for c in s.chars() {
        v = v * 10 + ((c - '0') as u64);
    }
    return Some(v);
}

fn main() {
    let args: Vec<String> = std::env::args().collect::<String>();
    if args.len() != 2 {
        eprintln!("error: expected exactly one argument N (0..93)");
        std::process::exit(1);
    }
    let s: &str = args[1].to_str();
    if let Some(n) = parse_num(s) {
        if n > 93 {
            eprintln!("error: N must be a non-negative integer in 0..93");
            std::process::exit(1);
        }
        println!("{}", fib(n));
    } else {
        eprintln!("error: N must be a non-negative integer in 0..93");
        std::process::exit(1);
    }
}
REOF

cat > /app/polyglot/run_checks.py <<'PCEOF'
#!/usr/bin/env python3
"""Cross-engine harness for the polyfibo tool.

Compiles the C and C++ modes and the Rust mode into /tmp, then runs all four
engines over every (N, expected) row in the fixture and checks error behavior.
Prints per-engine PASS/FAIL, then ALL PASS / FAIL and writes status.txt.
"""
import os
import subprocess
import sys

BASE = "/app/polyglot"
MC = os.path.join(BASE, "main.c")
MR = os.path.join(BASE, "main.rs")
FIX = os.path.join(BASE, "expected_fib.txt")
TMP = "/tmp"
cm = os.path.join(TMP, "cm")
cmm = os.path.join(TMP, "cmm")
rm = os.path.join(TMP, "rm")

engines = {}


def build():
    out = {}
    out["python"] = (["python3", MC], "python3 main.c N")
    ok = True
    r = subprocess.run(["gcc", MC, "-o", cm])
    if r.returncode == 0:
        out["c"] = ([cm], "gcc main.c N")
    else:
        ok = False
    r = subprocess.run(["g++", "-x", "c++", MC, "-o", cmm])
    if r.returncode == 0:
        out["cpp"] = ([cmm], "g++ -x c++ main.c N")
    else:
        ok = False
    r = subprocess.run(["rustc", MR, "-o", rm])
    if r.returncode == 0:
        out["rust"] = ([rm], "rustc main.rs N")
    else:
        ok = False
    global engines
    engines = out
    return ok


def run_engine(name, n):
    opts, _ = engines[name]
    if name == "python":
        cmd = ["python3", MC, str(n)]
    else:
        cmd = opts + [str(n)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def run_err(name, arg):
    opts, _ = engines[name]
    if name == "python":
        cmd = ["python3", MC] + ([arg] if arg is not None else [])
    else:
        cmd = opts + ([arg] if arg is not None else [])
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def main():
    ok = build()

    def check(name, okk):
        global ok
        print("ENGINE %s: %s" % (name, "PASS" if okk else "FAIL"))
        if not okk:
            ok = False

    # load expected fibonacci table
    rows = []
    for line in open(FIX):
        line = line.strip()
        if not line:
            continue
        n, want = line.split()
        rows.append((int(n), int(want)))

    for name in list(engines):
        good = True
        for n, want in rows:
            rc, out, err = run_engine(name, n)
            if rc != 0 or out != str(want):
                good = False
                break
        for bad in (None, "abc", "-1"):
            rc, out, err = run_err(name, bad)
            if rc == 0 or not err:
                good = False
                break
        check(name, good)

    run_checks_ok = (set(engines) == {"python", "c", "cpp", "rust"}) and ok
    status = "PASS" if run_checks_ok else "FAIL"
    with open(os.path.join(BASE, "status.txt"), "w") as f:
        f.write(status + "\n")
    if run_checks_ok:
        print("ALL PASS")
        sys.exit(0)
    print("FAIL summary")
    sys.exit(1)


if __name__ == "__main__":
    main()
PCEOF

python3 /app/polyglot/run_checks.py
echo "leave main.c, main.rs, run_checks.py, status.txt in /app/polyglot"