#!/usr/bin/env python3
"""Verifier for umber-engine. Executes every deliverable on hidden inputs via
test.sh (which first compiles /app/seq.rs -> /app/seq_rs). reward=1 only if all
checks pass. Independent of the oracle: it recomputes the sequence and the wasm
byte formula from the documented constants, and independently reads the wasm
linear memory from the host side."""
import json, os, re, subprocess, sys, tempfile

cd = "/app"
HIDDEN = "/tests/hidden"


def oracle_seq(n):
    if n < 0 or n > 100:
        return None
    P = [1, 1, 1]
    for k in range(3, n + 1):
        P.append(P[k - 2] + P[k - 3])
    return P[n]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def fail(msg):
    print("VERIFY FAIL: " + msg)
    return False


def check_seq(terms):
    for n in terms:
        exp = oracle_seq(n)
        rc_py, out_py, _ = run([sys.executable, f"{APP}/seq.py", str(n)])
        rc_rs, out_rs, _ = run([f"{APP}/seq_rs", str(n)])
        if rc_py != 0 or out_py != str(exp):
            return fail(f"seq.py({n}) -> rc={rc_py} out={out_py!r} exp={exp}")
        if rc_rs != 0 or out_rs != str(exp):
            return fail(f"seq_rs({n}) -> rc={rc_rs} out={out_rs!r} exp={exp}")
        if out_py != out_rs:
            return fail(f"runtimes disagree at n={n}: py={out_py} rs={out_rs}")
    return True


def check_safe_rust():
    src = open(f"{APP}/seq.rs").read()
    for token in ["unsafe", "extern", "no_mangle", "repr(C)", "std::ffi", "ffi::", "link("]:
        if token in src:
            return fail(f"seq.rs contains forbidden construct {token!r}")
    return True


def check_wasm(seeds):
    wmod = "/tmp/wc.wasm"
    cc = run(["clang", "--target=wasm32-unknown-unknown", "-O2", "-nostdlib",
              "-Wl,--no-entry", "-Wl,--export-all", "-o", wmod, f"{APP}/wasm.c"])
    if cc[0] != 0 or not os.path.exists(wmod):
        return fail("clang wasm compile failed: " + cc[2][:400])
    import wasmtime
    from wasmtime import Store, Module, Instance
    st = Store()
    mod = Module.from_file(st.engine, wmod)
    ins = Instance(st, mod, [])
    x = ins.exports(st)
    for need in ("boot", "producer", "consumer", "memory", "buffer"):
        if need not in x:
            return fail(f"wasm missing export {need}")
    boot, producer, consumer = x["boot"], x["producer"], x["consumer"]
    memory = x["memory"]
    base = x["buffer"].value(st)
    boot(st)

    def byte(i):
        return (i * 13 + 7) & 0xFF

    sums = []
    for seed in seeds:
        off = int(producer(st, seed))
        if not (0 <= off <= 239):
            return fail(f"offset out of range for seed {seed}: {off}")
        got = int(consumer(st, off))
        lo, hi = int(base) + off, int(base) + off + 16
        data = memory.read(st, lo, hi)
        if len(data) != 16:
            return fail(f"read length {len(data)} != 16 at seed {seed}")
        expected = [byte(off + k) for k in range(16)]
        if list(data) != expected:
            return fail(f"memory bytes mismatched at seed {seed} (offset {off})")
        if got != sum(expected):
            return fail(f"consumer={got} != expected {sum(expected)} at seed {seed}")
        sums.append(got)
    return True


def check_grpc():
    code, out, err = run([sys.executable, "-c",
                          "import grpc, grpc_tools; from grpc_tools import protoc; print('ok')"])
    if code != 0 or out != "ok":
        return fail("grpc/grpc_tools not importable system-wide: " + err)
    # codegen a proto and import the generated modules (system-wide codegen works)
    for src in (f"{APP}/echo.proto", f"{HIDDEN}/h3_echo.proto"):
        base = os.path.basename(src).split(".")[0]
        inc = os.path.dirname(src)
        gen = tempfile.mkdtemp()
        r = run([sys.executable, "-m", "grpc_tools.protoc", "-I" + inc,
                 f"--python_out={gen}", f"--grpc_python_out={gen}", src])
        if r[0] != 0:
            return fail("protoc codegen failed: " + r[2][:300])
        sys.path.insert(0, gen)
        try:
            import importlib
            importlib.import_module(base + "_pb2")
            importlib.import_module(base + "_pb2_grpc")
        except Exception as e:
            return fail("generated grpc module import failed: " + repr(e)[:200])
    return True


def main():
    global APP
    APP = "/app"
    hidden = {}
    if os.path.isdir(HIDDEN):
        for fn in os.listdir(HIDDEN):
            if fn.endswith(".json"):
                p = os.path.join(HIDDEN, fn)
                hidden.update(json.load(open(p)))

    visible_terms = [0, 1, 2, 3, 10, 40, 60]
    visible_seeds = [0, 1, 7, 42]
    terms = visible_terms + hidden.get("terms", [])
    seeds = visible_seeds + hidden.get("seeds", [])

    ok = True
    if not os.path.exists(f"{APP}/seq.py"):
        ok = fail("missing /app/seq.py")
    if not os.path.exists(f"{APP}/seq.rs"):
        ok = fail("missing /app/seq.rs")
    if not os.path.exists(f"{APP}/wasm.c"):
        ok = fail("missing /app/wasm.c")
    if ok:
        ok = check_safe_rust() and check_seq(terms) and check_wasm(seeds)
    if ok:
        ok = check_grpc()
    print("UMBER_ENGINE_OK" if ok else "UMBER_ENGINE_FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())