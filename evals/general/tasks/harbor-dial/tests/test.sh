#!/bin/bash
# harbor-dial verifier: executes all three deliverables against hidden scenarios.
# Reward is written to /logs/verifier/reward.txt.
mkdir -p /logs/verifier

python3 - <<'PY'
import json, glob, os, importlib.util, tempfile, subprocess, re, asyncio
import numpy as np

failures = []
def fail(msg):
    failures.append(msg)
    print("FAIL:", msg)

def have(p):
    if not os.path.exists(p):
        fail("missing deliverable " + p)
        return False
    return True

def which(name):
    for d in os.environ.get("PATH", "").split(":"):
        if d and os.path.isfile(os.path.join(d, name)):
            return os.path.join(d, name)
    return None

# ---------------------------------------------------------------------------
# PART A — pipeline_parallel.py
# ---------------------------------------------------------------------------
def check_pipeline():
    PIPE = "/app/pipeline_parallel.py"
    if not have(PIPE):
        return
    try:
        spec = importlib.util.spec_from_file_location("pipeline_parallel", PIPE)
        pp = importlib.util.module_from_spec(spec); spec.loader.exec_module(pp)
        for f in ("partition", "build", "stage_forward", "forward_all", "backward_all"):
            if not callable(getattr(pp, f, None)):
                fail("pipeline missing function " + f); return
    except Exception as e:
        fail("import pipeline_parallel: " + repr(e)); return

    for p in sorted(glob.glob("/tests/hidden/pipeline_*.json")):
        c = json.load(open(p))
        L, R, dims, batch, seed, isd = (c["num_layers"], c["num_ranks"], c["dims"],
                                        c["batch"], c["seed"], c["inp_seed"])
        try:
            # partition must cover every layer exactly once
            seen = []
            for r in range(R):
                part = pp.partition(L, R, r)
                if not (isinstance(part, list) and all(0 <= l < L for l in part)):
                    fail("partition malformed " + p); return
                seen += part
            if len(seen) != L or sorted(seen) != list(range(L)):
                fail("partition does not cover layers exactly " + p); return

            full = {}
            for r in range(R):
                bld = pp.build(L, R, r, dims, seed)
                for l, (W, b) in bld.items():
                    if not isinstance(W, np.ndarray) or W.shape != (dims[l], dims[l+1]):
                        fail("W wrong shape " + p); return
                    if not isinstance(b, np.ndarray) or b.shape != (dims[l+1],):
                        fail("b wrong shape " + p); return
                    if np.any(b != 0.0):
                        fail("b not zero-initialized " + p); return
                    full[l] = (np.asarray(W, float), np.asarray(b, float))

            x = np.random.RandomState(isd).randn(batch, dims[0])
            y = pp.forward_all(L, R, full, x)
            h = x.copy()
            for l in range(L):
                W, b = full[l]; h = np.tanh(h.dot(W) + b)
            if y.shape != h.shape or np.max(np.abs(y - h)) > 1e-6:
                fail("forward mismatch vs dense " + p); return

            grads, gx0 = pp.backward_all(L, R, full, x)
            for l in range(L):
                gW, gB = grads[l]
                if gW.shape != (dims[l], dims[l+1]) or gB.shape != (dims[l+1],):
                    fail("grad shape wrong " + p); return
            if gx0.shape != x.shape:
                fail("grad_input shape wrong " + p); return

            # finite-difference gradient check on sampled entries
            eps = 1.0e-3
            rng = np.random.RandomState(12345)
            def cpy():
                return {l: (full[l][0].copy(), full[l][1].copy()) for l in range(L)}
            def loss(fp):
                return float(0.5 * np.sum(np.asarray(pp.forward_all(L, R, fp, x))**2))

            nl = min(3, L)
            for l in rng.choice(list(range(L)), size=nl, replace=False):
                l = int(l)
                W, b = full[l]
                i = int(rng.randint(W.shape[0])); j = int(rng.randint(W.shape[1]))
                fpl = cpy(); fpl[l][0][i, j] = W[i, j] + eps
                fml = cpy(); fml[l][0][i, j] = W[i, j] - eps
                num = (loss(fpl) - loss(fml)) / (2 * eps)
                rel = abs(num - grads[l][0][i, j]) / max(1e-9, abs(num))
                if rel > 0.05:
                    fail("gradW FD mismatch %s rel=%.3g" % (p, rel)); return

            l0 = int(rng.choice(list(range(L)), size=1, replace=False)[0])
            b0 = full[l0][1]; k = int(rng.randint(b0.shape[0]))
            fpb = cpy(); fpb[l0][1][k] = b0[k] + eps
            fmb = cpy(); fmb[l0][1][k] = b0[k] - eps
            num = (loss(fpb) - loss(fmb)) / (2 * eps)
            rel = abs(num - grads[l0][1][k]) / max(1e-9, abs(num))
            if rel > 0.05:
                fail("gradB FD mismatch %s rel=%.3g" % (p, rel)); return
        except Exception as e:
            fail("pipeline case %s raised %r" % (p, e)); return
    print("pipeline OK")

# ---------------------------------------------------------------------------
# PART B — parallel_assembly.c -> build pgen, run, verify rank files
# ---------------------------------------------------------------------------
def check_assembly():
    SRCF = "/app/parallel_assembly.c"
    if not (have(SRCF) and have("/app/pgen")):
        return
    if not which("gcc"):
        fail("gcc unavailable"); return
    buildbin = os.path.join(tempfile.mkdtemp(), "pgen")
    if subprocess.call(["gcc", "-O2", "-pthread", "-o", buildbin, SRCF]) != 0:
        fail("cannot compile /app/parallel_assembly.c"); return

    def item_total(lo, hi):
        return sum((i * 1733 + 17) % 10007 for i in range(lo, hi))

    for p in sorted(glob.glob("/tests/hidden/assembly_*.json")):
        c = json.load(open(p))
        if c["kind"] == "assembly_bad":
            for argv in c["argv"]:
                work = tempfile.mkdtemp()
                r = subprocess.run([buildbin] + argv, cwd=work, capture_output=True)
                if r.returncode == 0:
                    fail("assembly_bad args %r exited 0" % (argv,)); return
                if glob.glob(os.path.join(work, "rank_*.out")):
                    fail("assembly_bad args %r wrote rank files" % (argv,)); return
            continue
        R_, items = c["num_ranks"], c["items"]
        work = tempfile.mkdtemp()
        r = subprocess.run([buildbin, str(R_), str(items)], cwd=work, capture_output=True)
        if r.returncode != 0:
            fail("assembly %s exited %d" % (p, r.returncode)); return
        out = sorted(glob.glob(os.path.join(work, "rank_*.out")))
        if len(out) != R_:
            fail("assembly %s produced %d files, expected %d" % (p, len(out), R_)); return
        names = [os.path.basename(o) for o in out]
        for rnum in range(R_):
            fname = "rank_%d.out" % rnum
            if fname not in names or not (fname.startswith("rank_") and fname.endswith(".out")):
                fail("assembly %s missing/wrong-name %s" % (p, fname)); return
            lo = (items * rnum) // R_; hi = (items * (rnum + 1)) // R_
            content = open(os.path.join(work, fname)).read()
            m = re.fullmatch(r"rank=(\d+)\nlo=(\d+)\nhi=(\d+)\ncount=(\d+)\ntotal=(\d+)\nok=true\r?(?:\n)?", content)
            if not m:
                fail("assembly file format wrong " + fname); return
            g = [int(v) for v in m.groups()]
            want = [rnum, lo, hi, hi - lo, item_total(lo, hi)]
            if g != want:
                fail("assembly %s rank %d got %r want %r" % (p, rnum, g, want)); return

    # Declared deliverables: actually execute the built binary on the visible
    # case and validate the per-rank output files it must have left under /app
    # (pgen 3 21 run from /app -> /app/rank_0.out, rank_1.out, rank_2.out).
    r = subprocess.run(["/app/pgen", "3", "21"],
                       cwd=tempfile.mkdtemp(), capture_output=True)
    if r.returncode != 0:
        fail("/app/pgen visible run exited %d" % r.returncode); return
    rank_files = sorted(glob.glob("/app/rank_*.out"))
    if len(rank_files) != 3:
        fail("expected 3 /app/rank_*.out files from ./pgen 3 21, got %d"
             % len(rank_files)); return
    for rnum in range(3):
        fname = "/app/rank_%d.out" % rnum
        if fname not in rank_files:
            fail("missing deliverable " + fname); return
        lo = (21 * rnum) // 3; hi = (21 * (rnum + 1)) // 3
        m = re.fullmatch(
            r"rank=(\d+)\nlo=(\d+)\nhi=(\d+)\ncount=(\d+)\ntotal=(\d+)\nok=true\r?(?:\n)?",
            open(fname, encoding="utf-8", errors="replace").read())
        want = [rnum, lo, hi, hi - lo, item_total(lo, hi)]
        if not m or [int(v) for v in m.groups()] != want:
            fail("deliverable %s content wrong: got %r want %r"
                 % (fname, m.groups() if m else None, want)); return
    print("assembly OK")

# ---------------------------------------------------------------------------
# PART C — asyncio pool
# ---------------------------------------------------------------------------
def check_asyncio():
    A = "/app/asyncio_pool.py"
    if not have(A):
        return
    try:
        spec = importlib.util.spec_from_file_location("asyncio_pool", A)
        ap = importlib.util.module_from_spec(spec); spec.loader.exec_module(ap)
        if not callable(getattr(ap, "run_capped", None)) or not hasattr(ap, "AsyncPool"):
            fail("asyncio_pool missing run_capped/AsyncPool"); return
    except Exception as e:
        fail("import asyncio_pool: " + repr(e)); return

    async def case(jobs, cap):
        active = [0]; mx = [0]
        async def job(i, d):
            active[0] += 1; mx[0] = max(mx[0], active[0])
            await asyncio.sleep(d); active[0] -= 1
            return i
        res = await ap.run_capped([job(i, 0.02) for i in range(jobs)], cap)
        return res, mx[0]

    async def empty():
        return await ap.run_capped([], 3)

    for p in sorted(glob.glob("/tests/hidden/async_*.json")):
        c = json.load(open(p))
        kind = c["kind"]
        try:
            if kind == "async_empty":
                if asyncio.run(empty()) != []:
                    fail("async empty not [] " + p); return
                continue
            if kind == "async_cancel":
                marker = []
                async def jc(i):
                    marker.append(i)
                    await asyncio.sleep(2.0)
                    return i
                cap, jobs = c["cap"], c["jobs"]
                async def main():
                    tsk = asyncio.create_task(ap.run_capped([jc(i) for i in range(jobs)], cap))
                    await asyncio.sleep(0.2)
                    tsk.cancel()
                    try:
                        await tsk
                    except asyncio.CancelledError:
                        pass
                asyncio.run(main())
                if not (0 < len(marker) <= cap):
                    fail("cancel started %d, cap %d" % (len(marker), cap)); return
                continue
            jobs, cap = c["jobs"], c["cap"]
            res, mx = asyncio.run(case(jobs, cap))
            if res != list(range(jobs)):
                fail("order/count wrong " + p); return
            if mx > cap:
                fail("concurrency %d > cap %d " % (mx, cap)); return
        except Exception as e:
            fail("async case %s raised %r" % (p, e)); return
    print("asyncio OK")

check_pipeline()
check_assembly()
check_asyncio()

with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not failures else "0")
print("failures:", len(failures))
PY