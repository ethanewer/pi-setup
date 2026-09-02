#!/bin/bash
# Verifier for hazel-forge: imports the deliverable /app/rungate.py and runs it
# on the visible self-test artifact plus every hidden job batch under
# /tests/hidden. Writes 0/1 to /logs/verifier/reward.txt. Never crashes on a
# broken agent module: every check is guarded.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import asyncio, importlib.util, json, os, subprocess, sys

MOD = "/app/rungate.py"
failures = []


def log(*a):
    print("[verifier]", *a)


def load_mod():
    if not os.path.isfile(MOD):
        return None
    try:
        spec = importlib.util.spec_from_file_location("rungate", MOD)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as e:
        log("import failed:", repr(e))
        return None


def check_selftest():
    path = "/app/selftest.json"
    if not os.path.isfile(path):
        failures.append("missing /app/selftest.json")
        return
    try:
        with open(path) as fh:
            rep = json.load(fh)
    except Exception as e:
        failures.append("selftest.json unreadable: %r" % e)
        return
    if not isinstance(rep, dict):
        failures.append("selftest.json not an object")
        return
    if set(rep.keys()) != {"limit", "jobs", "results", "peak_concurrency", "ok"}:
        failures.append("selftest.json wrong keys: %r" % sorted(rep.keys()))
        return
    want = [i * i for i in range(rep.get("jobs", -1))] \
        if rep.get("jobs") == 10 else None
    if rep.get("jobs") != 10 or rep.get("limit") != 4:
        failures.append("selftest.json wrong jobs/limit")
        return
    if rep.get("results") != want:
        failures.append("selftest.json wrong results")
        return
    if not isinstance(rep.get("ok"), bool) or not rep["ok"]:
        failures.append("selftest.json ok != true")
        return
    peak = rep.get("peak_concurrency")
    if not isinstance(peak, int) or not (1 <= peak <= 4):
        failures.append("selftest.json peak_concurrency out of range: %r" % (peak,))


# --- hidden case runner -----------------------------------------------------
async def run_cases(mod, hidden):
    for name in sorted(os.listdir(hidden)):
        base = os.path.join(hidden, name)
        spec_path = os.path.join(base, "spec.json")
        if not os.path.isfile(spec_path):
            failures.append("hidden '%s': missing spec.json" % name)
            continue
        try:
            with open(spec_path) as fh:
                spec = json.load(fh)
        except Exception as e:
            failures.append("hidden '%s': unreadable spec (%r)" % (name, e))
            continue
        try:
            await run_case(name, mod, spec)
        except Exception as e:
            failures.append("hidden '%s': verifier harness error %r" % (name, e))


async def run_case(name, mod, spec):
    limit = spec["limit"]
    jobs = spec["jobs"]
    exp = spec.get("expected", {})
    mode = exp.get("mode", "run")

    called = []
    live = 0
    peak = [0]

    def make_factory(i, dur_ms, fail):
        async def job():
            called.append(i)
            live_inc = None
            await asyncio.sleep(dur_ms / 1000.0)
            if fail:
                raise ValueError("boom")
            return i * i
        return job

    def wrap(factory):
        async def guarded():
            nonlocal live
            live += 1
            peak[0] = max(peak[0], live)
            try:
                return await factory()
            finally:
                live -= 1
        return guarded

    async def build():
        out = []
        for i, j in enumerate(jobs):
            f = make_factory(i, j["dur_ms"], j.get("fail", False))
            out.append(wrap(f))
        return out

    factories = await build()
    gate = mod.RunGate(limit)
    task = asyncio.ensure_future(gate.run_jobs(factories))

    if mode == "cancel":
        await asyncio.sleep(exp.get("cancel_after_ms", 100) / 1000.0)
        task.cancel()
        try:
            await task
            failures.append("hidden '%s': cancellation did not propagate"
                            % name)
        except asyncio.CancelledError:
            max_started = exp.get("max_started", limit)
            if len(called) > max_started:
                failures.append(
                    "hidden '%s': %d jobs ran after cancellation (max %d)"
                    % (name, len(called), max_started))
        return

    if mode == "raises":
        try:
            await task
            failures.append("hidden '%s': expected %s, got success"
                            % (name, exp.get("exc", "exception")))
        except Exception as e:
            if type(e).__name__ != exp.get("exc", type(e).__name__):
                failures.append("hidden '%s': wrong exception %r" % (name, e))
            max_called = exp.get("max_factories_called", len(jobs))
            if len(called) > max_called:
                failures.append(
                    "hidden '%s': %d factories called after failure (max %d)"
                    % (name, len(called), max_called))
            for idx in exp.get("must_call_index", []):
                if idx not in called:
                    failures.append("hidden '%s': job %d never started"
                                    % (name, idx))
        return

    # mode == run
    try:
        results = await asyncio.wait_for(task, timeout=60)
    except Exception as e:
        failures.append("hidden '%s': batch raised %r" % (name, e))
        return
    want = [i * i for i in range(len(jobs))]
    if results != want:
        failures.append("hidden '%s': wrong results (%r...)" % (name, results[:4]))
        return
    if len(called) != len(jobs):
        failures.append("hidden '%s': each factory must run exactly once"
                        % name)
        return
    max_peak = exp.get("max_peak", limit)
    if peak[0] > max_peak:
        failures.append("hidden '%s': peak concurrency %d > %d"
                        % (name, peak[0], max_peak))
    if peak[0] < 1 and jobs:
        failures.append("hidden '%s': no job ever ran" % name)


def main():
    mod = load_mod()
    if mod is None:
        failures.append("cannot import /app/rungate.py")
        return
    gate_cls = getattr(mod, "RunGate", None)
    if gate_cls is None:
        failures.append("no RunGate class")
        return
    # construction guard
    for bad in (0, -2):
        try:
            gate_cls(bad)
            failures.append("RunGate(%d) did not raise ValueError" % bad)
        except ValueError:
            pass
        except Exception as e:
            failures.append("RunGate(%d) raised %r" % (bad, e))
    # empty batch
    try:
        got = asyncio.run(mod.RunGate(2).run_jobs([]))
        if got != []:
            failures.append("run_jobs([]) != []")
    except Exception as e:
        failures.append("run_jobs([]) raised %r" % e)
    check_selftest()
    hidden = "/tests/hidden"
    if os.path.isdir(hidden) and os.listdir(hidden):
        asyncio.run(run_cases(mod, hidden))
    else:
        failures.append("no hidden cases present")


main()
print("verify failures:", failures)
sys.exit(1 if failures else 0)
PYEOF
rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
