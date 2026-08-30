#!/usr/bin/env python3
"""Verifier for arid-jetty. Independent of the oracle implementation style: it
re-derives every behavior from the /app/solve.py API contract, replays the
emitted Vimscript in a fresh `vim -u NONE`, and checks answer.json consistency,
then exercises the hidden cases (edge values, malformed wasm, iteration-constant
override). Exit 0 => reward 1."""

import glob
import json
import os
import subprocess
import sys

APP = "/app"
DATADIR = os.path.join(APP, "data")
sys.path.insert(0, APP)
sys.path.insert(0, DATADIR)

FAILED = []


def fail(msg):
    FAILED.append(msg)
    print("FAIL:", msg, file=sys.stderr)


def ok(x, label):
    return x


# ---------------------------------------------------------------------------
# 0. deliverables exist
# ---------------------------------------------------------------------------
if not os.path.exists(os.path.join(APP, "solve.py")):
    print(json.dumps({"reward": 0, "failures": ["/app/solve.py missing"]}))
    sys.exit(1)

import solve  # noqa: E402


# ---------------------------------------------------------------------------
# 1. answer.json consistency (recompute each value independently)
# ---------------------------------------------------------------------------
if not os.path.exists(os.path.join(APP, "answer.json")):
    fail("/app/answer.json missing (run solve.py with no args)")
    print(json.dumps({"reward": 0, "failures": FAILED}))
    sys.exit(0)

ans = json.load(open(os.path.join(APP, "answer.json")))

woff, wbyte = solve.wasm_probe()
if ans.get("wasm_offset") != woff:
    fail("answer.json wasm_offset=%r != recomputed %r" % (ans.get("wasm_offset"), woff))
if ans.get("wasm_byte") != wbyte:
    fail("answer.json wasm_byte=%r != recomputed %r" % (ans.get("wasm_byte"), wbyte))

if ans.get("closure") != solve.closure_probe():
    fail("answer.json closure snapshot != recomputed closure_probe()")

if ans.get("iterations") != solve.get_iterations():
    fail("answer.json iterations != recomputed get_iterations()")

if ans.get("parallel_len") != len(solve.compute_parallel()):
    fail("answer.json parallel_len != recomputed compute_parallel()")

sig = solve.hash_signature()
if not all(sig.values()):
    fail("solve.hash_signature() has a false invariant: %r" % sig)
if ans.get("hash_consistent") is not True:
    fail("answer.json hash_consistent not true")

if ans.get("vim_script") != os.path.join(APP, "recreate.vim"):
    fail("answer.json vim_script != /app/recreate.vim")
if not os.path.exists(os.path.join(APP, "recreate.vim")):
    fail("/app/recreate.vim missing")


# ---------------------------------------------------------------------------
# 2. wasm exported function returns a memory offset we can read back
# ---------------------------------------------------------------------------
if not (isinstance(woff, int) and 0 <= woff < 65536):
    fail("wasm offset not a plausible memory index: %r" % woff)
if not (isinstance(wbyte, int) and 0 <= wbyte <= 255):
    fail("wasm byte at offset not a 0..255 byte: %r" % wbyte)


# ---------------------------------------------------------------------------
# 3. higher-order closures / currying / mutual recursion (visible checks)
# ---------------------------------------------------------------------------
inc, dec = solve.make_counter(10)
steps = [inc(2), inc(1), dec(20), inc(7)]
if steps != [12, 13, -7, 0]:
    fail("make_counter steps mismatch: %r" % steps)
if solve.curry_add(4)(5) != 9:
    fail("curry_add failed")
if solve.curry_add(4)(5, 3) != 12:
    fail("curry_add variadic form failed")
if solve.mutual_even(12) is not True or solve.mutual_odd(13) is not True:
    fail("mutual recursion even/odd wrong")
if solve.mutual_even(-6) is not True or solve.mutual_odd(-7) is not True:
    fail("mutual recursion negative normalization wrong")


# ---------------------------------------------------------------------------
# 4. object hash consistent with equality (visible checks)
# ---------------------------------------------------------------------------
a = solve.Point(2, 3)
b = solve.Point(2, 3)
c = solve.Point(2, 4)
if not (a == b):
    fail("equal Points not equal")
if hash(a) != hash(b):
    fail("equal Points hash differently")
if a == c or hash(a) == hash(c):
    fail("unequal Points collide on value-hash")


# ---------------------------------------------------------------------------
# 5. iteration constant imported (not restated inline)
# ---------------------------------------------------------------------------
src = open(os.path.join(APP, "solve.py")).read()
if "731" in src:
    fail("solve.py hardcodes the sequential iteration constant 731 inline")
if "compute_seq" not in src:
    fail("solve.py does not reference the compute_seq module at all")
if solve.get_iterations() != 731:
    fail("get_iterations() != 731")
if len(solve.compute_parallel()) != 731:
    fail("compute_parallel() length != 731")


# ---------------------------------------------------------------------------
# 6. Vimscript replay in a fresh `vim -u NONE`
# ---------------------------------------------------------------------------
INSPECTOR = r'''
function! DumpLayout() abort
  let lines = []
  for t in range(1, tabpagenr("$"))
    execute "tabnext " . t
    let bufs = []
    for w in range(1, winnr("$"))
      call add(bufs, fnamemodify(bufname(winbufnr(w)), ":t"))
    endfor
    call sort(bufs)
    call add(lines, "TAB" . t . ":" . join(bufs, ","))
  endfor
  call writefile(lines, "/tmp/vim_layout.txt")
endfunction
call DumpLayout()
qa!
'''


def replay(vimscript_path):
    work = "/tmp"
    insp = os.path.join(work, "inspect_layout.vim")
    with open(insp, "w") as fh:
        fh.write("source %s\n" % vimscript_path)
        fh.write(INSPECTOR)
    layout = os.path.join(work, "vim_layout.txt")
    if os.path.exists(layout):
        os.remove(layout)
    import pty
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm"
        os.execvp("vim", ["vim", "-u", "NONE", "-n", "-N", "-c", "source " + insp])
    os.waitpid(pid, 0)
    if not os.path.exists(layout):
        return None
    with open(layout) as fh:
        data = [ln for ln in fh.read().splitlines() if ln.strip()]
    return data


def check_layout(lines, expect_tabs, expect_bufs):
    """expect_bufs: {tab_index: set(buffer_names_on_that_tab)}"""
    if lines is None:
        fail("vim replay produced no layout file")
        return False
    got = {}
    for ln in lines:
        if ln.startswith("TAB") and ":" in ln:
            idx, _, names = ln.partition(":")
            bufset = set(n for n in names.split(",") if n)
            got[idx] = bufset
    for tidx in expect_bufs:
        if tidx not in got:
            fail("vim replay missing tab %s (got %r)" % (tidx, got))
            return False
        if got[tidx] != expect_bufs[tidx]:
            fail("vim replay tab %s buffers %r != expected %s" %
                 (tidx, got[tidx], expect_bufs[tidx]))
            return False
    return True


exp = {"TAB1": {"alpha.txt", "beta.txt"}, "TAB2": {"gamma.txt"}}
recorded = replay(os.path.join(APP, "recreate.vim"))
check_layout(recorded, len(exp), exp)

# reproducibility: a freshly emitted Vimscript must be byte-identical and replay
# to the same topology.
fresh = os.path.join(APP, "recreate_fresh.vim")
if os.path.exists(fresh):
    os.remove(fresh)
solve.emit_vimscript(fresh)
try:
    same_file = open(fresh, "rb").read() == open(os.path.join(APP, "recreate.vim"), "rb").read()
    if not same_file:
        fail("freshly emitted Vimscript differs from /app/recreate.vim")
    check_layout(replay(fresh), len(exp), exp)
finally:
    if os.path.exists(fresh):
        os.remove(fresh)


# ---------------------------------------------------------------------------
# 7. hidden cases
# ---------------------------------------------------------------------------
def read_hidden():
    import glob as _glob
    return sorted(_glob.glob("/tests/hidden/*.json"))


hidden = read_hidden()
if not hidden:
    fail("no hidden case files found in /tests/hidden")

for case_path in hidden:
    case = json.load(open(case_path))
    kind = case.get("kind")
    if kind == "closure":
        for c in case.get("cases", []):
            c_inc, c_dec = solve.make_counter(c.get("start", 0))
            got = []
            for op, by in c.get("steps", []):
                got.append(c_inc(by) if op == "inc" else c_dec(by))
            if c.get("expected", None) is not None and got != c["expected"]:
                fail("%s: closure steps got=%r expected=%r" % (case.get("id"), got, c["expected"]))
            if "curry" in c:
                cu = c["curry"]
                if solve.curry_add(cu["a"])(cu["b"]) != cu["expect"]:
                    fail("%s: curry got mismatch" % case.get("id"))
            for r in c.get("recursion", []):
                fn = solve.mutual_even if r[0] == "even" else solve.mutual_odd
                if fn(r[1]) != r[2]:
                    fail("%s: recursion %s(%d) != %r" % (case.get("id"), r[0], r[1], r[2]))
    elif kind == "hash":
        for p in case.get("pairs", []):
            pa = solve.Point(p["p"][0], p["p"][1])
            pqa = solve.Point(p["q"][0], p["q"][1])
            eq = pa == pqa
            if eq != p["equal"]:
                fail("%s: Point equality got=%r expected=%r" % (case.get("id"), eq, p["equal"]))
            if eq and hash(pa) != hash(pqa):
                fail("%s: equal Points hash differently" % case.get("id"))
            if not eq and hash(pa) == hash(pqa):
                fail("%s: unequal Points hash-collided" % case.get("id"))
    elif kind == "wasm":
        for w in case.get("cases", []):
            try:
                solve.wasm_probe(w["binary"])
                had_err = False
            except ValueError:
                had_err = True
            except Exception:
                had_err = True
            if not had_err:
                fail("%s: wasm_probe(%s) should have raised but did not" %
                     (case.get("id"), w["binary"]))
    elif kind == "iter":
        import compute_seq
        orig = compute_seq.ITERATIONS
        compute_seq.ITERATIONS = case["override"]
        got_len = len(solve.compute_parallel())
        compute_seq.ITERATIONS = orig
        if got_len != case["expect_len"]:
            fail("%s: after overriding ITERATIONS to %d, compute_parallel() length "
                 "got=%d expected=%d (hardcoded value would not track the imported "
                 "constant)" % (case.get("id"), case["override"], got_len, case["expect_len"]))
    else:
        fail("unknown hidden case kind %r in %s" % (kind, case_path))

# ---------------------------------------------------------------------------
verdict = {"reward": 1 if not FAILED else 0, "failures": FAILED}
print(json.dumps(verdict, indent=2))
sys.exit(0 if not FAILED else 1)