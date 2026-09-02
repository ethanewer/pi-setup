#!/bin/bash
set -euo pipefail

# Correct dispatcher: remove the spurious double-release. LeasePool.hold() is
# the only class that touches `_live`.
cat > /app/dispatcher.py <<'PYEOF'
import asyncio
from contextlib import asynccontextmanager


class LeasePool:
    def __init__(self):
        self._live = 0

    @property
    def live(self):
        return self._live

    @asynccontextmanager
    async def hold(self):
        self._live += 1
        try:
            yield
        finally:
            self._live -= 1


class Dispatcher:
    def __init__(self, max_concurrency: int):
        if not isinstance(max_concurrency, int) or max_concurrency < 1:
            raise ValueError("max_concurrency must be a positive int")
        self.max_concurrency = max_concurrency
        self.leases = LeasePool()

    async def _guarded(self, coro):
        async with self._sem:
            async with self.leases.hold():
                return await coro

    async def dispatch(self, coros):
        self._sem = asyncio.Semaphore(self.max_concurrency)
        tasks = [asyncio.create_task(self._guarded(c)) for c in coros]
        try:
            return await asyncio.gather(*tasks)
        except BaseException:
            for t in tasks:
                if not t.done():
                    t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            raise
PYEOF

# Race/fuzz test exercising the cancellation path many times.
mkdir -p /app/tests
cat > /app/tests/test_behavior.py <<'PYEOF'
import asyncio
import sys

import pytest

sys.path.insert(0, "/app")
from dispatcher import Dispatcher, LeasePool

def run(coro):
    return asyncio.run(coro)

def job(state, n, delay=0.4, fail=False):
    async def _do():
        state["cur"] += 1
        state["peak"] = max(state["peak"], state["cur"])
        try:
            await asyncio.sleep(delay)
            if fail:
                raise RuntimeError(f"job {n}")
            return n * 10
        finally:
            state["cur"] -= 1
    return _do()

@pytest.mark.parametrize("limit", [1, 2, 4, 8])
def test_normal_accounting_and_cap(limit):
    for _ in range(10):
        d = Dispatcher(limit)
        st = {"cur": 0, "peak": 0}
        n = limit * 3
        res = run(d.dispatch([job(st, i, 0.02) for i in range(n)]))
        assert res == [i * 10 for i in range(n)]
        assert st["peak"] <= limit
        assert d.leases.live == 0
        assert st["cur"] == 0

@pytest.mark.parametrize("limit", [1, 2, 4, 8])
@pytest.mark.parametrize("repeat", range(12))
def test_cancel_never_negative(limit, repeat):
    async def scenario():
        d = Dispatcher(limit)
        st = {"cur": 0, "peak": 0}
        n = limit * 3
        jobs = [job(st, i) for i in range(n)]
        seen_min = 10**9
        runner = asyncio.create_task(d.dispatch([
            job(st, i) for i in range(n)
        ]))
        await asyncio.sleep(0.02)
        runner.cancel()
        try:
            await runner
            raise AssertionError("expected cancellation")
        except asyncio.CancelledError:
            pass
        return d.leases.live, st["cur"]
    # Use Dispatcher per scenario, track live never negative.
    live, cur = run(scenario())
    assert (live, cur) == (0, 0), (limit, live, cur)
    assert live >= 0
PYEOF