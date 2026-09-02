#!/bin/bash
# Oracle for hazel-forge: write the deliverable module /app/rungate.py, run its
# self-test CLI to produce /app/selftest.json, and sanity-import it.
# Never reads /tests.
set -eu

MOD="/app/rungate.py"
OUT="/app/selftest.json"

cat > "$MOD" <<'PY'
"""RunGate: an asyncio scheduler with a hard max-concurrency limit."""
import argparse
import asyncio
import json


class RunGate:
    """Runs a batch of job factories with at most `limit` executing at once."""

    def __init__(self, limit: int):
        if limit < 1:
            raise ValueError("limit must be >= 1, got %r" % (limit,))
        self.limit = limit
        self.peak_concurrency = 0

    async def run_jobs(self, factories) -> list:
        if not factories:
            return []
        sem = asyncio.Semaphore(self.limit)
        live = 0
        results = [None] * len(factories)
        tasks = []

        async def run_one(index, factory):
            nonlocal live
            # Acquire the gate BEFORE the job is wrapped/launched, so no job
            # starts executing while `limit` others are running.
            async with sem:
                live += 1
                if live > self.peak_concurrency:
                    self.peak_concurrency = live
                try:
                    results[index] = await factory()
                finally:
                    live -= 1

        for i, factory in enumerate(factories):
            tasks.append(asyncio.ensure_future(run_one(i, factory)))
        try:
            await asyncio.gather(*tasks)
        except BaseException:
            for t in tasks:
                if not t.done():
                    t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            raise
        return results


async def gather_capped(factories, limit: int) -> list:
    return await RunGate(limit).run_jobs(factories)


def _selftest(out_path: str) -> int:
    import time

    async def main():
        async def make_job(i):
            async def job():
                await asyncio.sleep(0.01 + 0.01 * (i % 3))
                return i * i
            return job

        gate = RunGate(4)
        factories = [await make_job(i) for i in range(10)]
        results = await gate.run_jobs(factories)
        report = {
            "limit": 4,
            "jobs": 10,
            "results": results,
            "peak_concurrency": gate.peak_concurrency,
            "ok": results == [i * i for i in range(10)]
            and 1 <= gate.peak_concurrency <= 4,
        }
        with open(out_path, "w") as fh:
            json.dump(report, fh, indent=2)
        return 0 if report["ok"] else 1

    return asyncio.run(main())


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", metavar="OUT_JSON")
    args = ap.parse_args()
    raise SystemExit(_selftest(args.selftest))
PY

chmod +x "$MOD"

# Sanity import + produce the deliverable by executing the CLI.
python3 -c "import importlib.util; s=importlib.util.spec_from_file_location('rungate','/app/rungate.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); assert hasattr(m,'RunGate') and hasattr(m,'gather_capped')"
python3 "$MOD" --selftest "$OUT"

echo "solve.sh done -> $MOD and $OUT"
ls -l "$MOD" "$OUT"
