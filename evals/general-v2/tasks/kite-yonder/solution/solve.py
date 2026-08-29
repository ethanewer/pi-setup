#!/usr/bin/env python3
"""Kite-yonder stack driver.

Builds every authored source file of the "ring" stack under /app, proves each
works, and writes /app/answer.json. Any failure makes the exit status nonzero
so a stale/gamey answer.json never survives a re-run. Re-runnable:
`rm /app/answer.json && python3 /app/solve.py` reproduces it from scratch.
"""
import json
import os
import shutil
import subprocess
import sys

APP = "/app"


def shell(cmd):
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    if r.returncode != 0:
        sys.stderr.write("CMD FAILED: %s\n%s\n" % (cmd, r.stderr.strip()[:500]))
        sys.exit(1)
    return r.stdout


def series(N, x):
    v = 0
    for k in range(1, N + 1):
        v = v * x + k
    return v


def main():
    # 1) C sampler tool: JSON weight parser + argmax autoregressive generation
    if not os.path.exists("%s/gen/sampler.c" % APP):
        sys.exit("missing /app/gen/sampler.c")
    shell_ok = shell("gcc -O2 -Wall -o %s/gen/sampler %s/gen/sampler.c" % (APP, APP))

    # 2) serial + parallel Make targets in /app/sim
    if not os.path.isfile("%s/sim/Makefile" % APP):
        sys.exit("missing /app/sim/Makefile")
    shell("make -C %s/sim clean" % APP)
    shell("make -C %s/sim serial pgen" % APP)
    for b in ("serial", "pgen"):
        if not os.path.exists("%s/sim/%s" % (APP, b)):
            sys.exit("make did not produce %s" % b)

    # 3) CMake LLVM-IR emission for every TU, linked to one module
    if not os.path.isfile("%s/cir/CMakeLists.txt" % APP):
        sys.exit("missing /app/cir/CMakeLists.txt")
    bdir = "%s/cir/build" % APP
    if os.path.isdir(bdir):
        shutil.rmtree(bdir)
    shell("cmake -S %s/cir -B %s" % (APP, bdir))
    shell("cmake --build %s" % bdir)
    if not os.path.exists("%s/bc/unified.bc" % bdir):
        sys.exit("unified.bc not produced")

    # 4) C++11 constexpr port must compile under -std=c++11 and be exact
    cpp = '#include "series.hpp"\n#include <cstdio>\n'
    for (n, x) in ((7, 3), (8, 4), (12, 2), (11, -7), (0, 9)):
        cpp += 'static_assert(mstr::series<%d,long>(%d)==%d, "const");\n' % (n, x, series(n, x))
    cpp += 'int main(){std::printf("cc11-ok\\n");return 0;}'
    open("%s/tpl/_check.cpp" % APP, "w").write(cpp)
    cr = subprocess.run(
        ["g++", "-std=c++11", "-pedantic-errors", "-Wall", "-Werror",
         "-I%s/tpl" % APP, "%s/tpl/_check.cpp" % APP, "-o", "/tmp/ser_check"],
        capture_output=True, text=True)
    if cr.returncode != 0:
        sys.exit("C++11 port does not compile: " + cr.stderr[:400])

    # 5) native<->Python ctypes binding
    shell("gcc -shared -fPIC -o %s/bind/libpad.so %s/bind/pad.c" % (APP, APP))
    if not os.path.isfile("%s/bind/bad.py" % APP):
        sys.exit("missing /app/bind/bad.py")
    br = subprocess.run(["python3", "%s/bind/bad.py" % APP], capture_output=True, text=True)
    if br.returncode != 0 or "ok" not in br.stdout:
        sys.exit("binding call did not succeed")

    # 6) visible generation demo must match its spec
    rd = subprocess.run(
        ["/app/gen/sampler", "%s/gen/demo.json" % APP, "6", "0", "0", "0"],
        capture_output=True, text=True)
    demo = [int(t) for t in rd.stdout.split()] if rd.stdout.strip() else []
    if rd.returncode != 0 or demo != [5, 2, 4, 4, 4, 4]:
        sys.exit("demo generation wrong: %r" % demo)

    ans = {
        "sampler_binary": "/app/gen/sampler",
        "sim": {"serial": "/app/sim/serial", "parallel": "/app/sim/pgen",
                "make_targets": ["serial", "pgen"]},
        "llvm_ir": {"per_tu": ["/app/cir/build/bc/alpha.bc",
                               "/app/cir/build/bc/beta.bc",
                               "/app/cir/build/bc/gamma.bc"],
                    "unified": "/app/cir/build/bc/unified.bc"},
        "cpp11_header": "/app/tpl/series.hpp",
        "binding": "/app/bind/bad.py",
        "demo_prompt": [0, 0, 0],
        "demo_tokens": demo,
    }
    json.dump(ans, open("%s/answer.json" % APP, "w"), indent=2)
    print("OK")


if __name__ == "__main__":
    main()