#!/usr/bin/env python3
"""
async_pool.py
-------------
Clean-room asyncio job scheduler with:
  * a hard concurrency cap (at most `cap` jobs are ever running at once), and
  * leak-free cancellation: when asked to stop after K jobs have STARTED, only
    those K (already-started) jobs may run; every queued-but-not-yet-started
    job is cancelled and NEVER executes.  A naive "gather everything then
    cancel" implementation leaks queued coroutines into execution -- exactly the
    defect this file is meant to avoid.

The scheduler admits jobs in FIFO order, one at a time, exactly up to the
number allowed to start.  Jobs that are never started stay in the local queue
and are reported as `never_started` / `cancelled`.  Progress is observed via a
start-order trace, a completion trace, and a running-max concurrency counter.

Importable API:
    async def run_batch(jobs, cap, trigger) -> dict

CLI (default writes /app/async_log.txt):
    python3 async_pool.py
    python3 async_pool.py --jobs 10 --cap 4 --trigger 4 --out /tmp/x.json
"""
import argparse
import asyncio
import json


def default_jobs(n):
    """Deterministic per-job work duration (0.04..0.55 s) so overlap happens."""
    return [0.04 + 0.09 * (i % 5) for i in range(n)]


async def run_batch(jobs, cap, trigger):
    """Run `jobs` (list of durations) with at most `cap` concurrent workers.

    `trigger` is the number of jobs allowed to START before the scheduler stops
    admitting more.  The remainder is cancelled and never started.
    * trigger <= 0  -> no job starts (everything is cancelled immediately).
    * trigger >= n  -> every job runs to completion (nothing is cancelled).
    Returns a snapshot dict (ready to JSON-serialize) with:
      cap, n, trigger, started (order), completed, never_started,
      max_concurrent, all_accounted flag.
    """
    cap = int(max(1, cap))
    n = len(jobs)
    limit = min(max(int(trigger), 0), n)  # number of jobs allowed to start

    pending = list(enumerate(jobs))       # (job_id, duration) not yet started
    inflight = {}
    started = []
    completed = set()
    active = 0
    max_concurrent = 0

    async def _run(job_id, dur):
        nonlocal active, max_concurrent
        active += 1
        max_concurrent = max(max_concurrent, active)
        try:
            await asyncio.sleep(dur)
            completed.add(job_id)
        finally:
            active -= 1

    while pending or inflight:
        # Admit new jobs only while we are under both the cap and the start limit.
        while (pend := pending) and len(inflight) < cap and len(started) < limit:
            job_id, dur = pending.pop(0)
            started.append(job_id)
            inflight[job_id] = asyncio.create_task(_run(job_id, dur))
        if not inflight:
            break  # nothing left running and nothing left to admit
        done, _ = await asyncio.wait(list(inflight.values()),
                                     timeout=20.0,
                                     return_when=asyncio.FIRST_COMPLETED)
        for t in done:
            # recover the id from the task
            for jid, tk in inflight.items():
                if tk is t:
                    del inflight[jid]
                    break

    never_started = sorted(set(range(n)) - set(started))
    return {
        "cap": int(cap),
        "n": int(n),
        "trigger": int(trigger),
        "limit": int(limit),
        "started": started,
        "completed": sorted(completed),
        "never_started": never_started,
        "cancelled": never_started,
        "max_concurrent": int(max_concurrent),
        "all_accounted": len(never_started) + len(started) == n,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description="asyncio job scheduler w/ cap")
    ap.add_argument("--jobs", type=int, default=6, help="number of jobs")
    ap.add_argument("--cap", type=int, default=3, help="concurrency cap")
    ap.add_argument("--trigger", type=int, default=3,
                    help="number of jobs to start before cancelling the rest")
    ap.add_argument("--out", default=None,
                    help="output path (default /app/async_log.txt)")
    args = ap.parse_args(argv)
    jobs = default_jobs(args.jobs)
    snap = asyncio.run(run_batch(jobs, args.cap, args.trigger))
    out = args.out or "/app/async_log.txt"
    with open(out, "w") as fh:
        fh.writelines(json.dumps(snap, indent=2) + "\n")
    return 0

if __name__ == "__main__":
    main()
