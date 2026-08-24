#!/bin/bash
set -euo pipefail

# Restore the correct, cleanup-guaranteed Dispatcher into /app/dispatcher.py.
cat > /app/dispatcher.py <<'PYEOF'
import asyncio
from contextlib import asynccontextmanager


class LeasePool:
    """Tracks the number of concurrently-held 'lease' slots."""

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
        # Bind the semaphore to the running loop at dispatch time.
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

# A passing stress/race test that the supplied contract test also verifies.
mkdir -p /app/tests
cat > /app/tests/test_behavior.py <<'PYEOF'
import asyncio
import sys

import pytest

sys.path.insert(0, "/app")
from dispatcher import Dispatcher

def run(coro):
    return asyncio.run(coro)

def job(state, n, delay=0.02, fail=False):
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

@pytest.mark.parametrize("limit", [1, 2, 3, 5, 8])
def test_cap_and_cleanup(limit):
    for _ in range(5):
        d = Dispatcher(limit)
        state = {"cur": 0, "peak": 0}
        n = limit * 3
        res = run(d.dispatch([job(state, i) for i in range(n)]))
        assert res == [i * 10 for i in range(n)]
        assert state["peak"] <= limit
        assert d.leases.live == 0
        assert state["cur"] == 0

@pytest.mark.parametrize("limit", [1, 2, 4])
def test_cancel_cleanup(limit):
    for _ in range(5):
        async def scenario():
            d = Dispatcher(limit)
            state = {"cur": 0, "peak": 0}
            n = limit * 3
            jobs = [job(state, i, delay=0.5) for i in range(n)]
            runner = asyncio.create_task(d.dispatch(jobs))
            await asyncio.sleep(0.02)
            runner.cancel()
            try:
                await runner
                raise AssertionError("expected cancellation")
            except asyncio.CancelledError:
                pass
            return d.leases.live, state["cur"]
        live, cur = run(scenario())
        assert (live, cur) == (0, 0)
PYEOF