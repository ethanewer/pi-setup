"""Supplied evaluator for the Dispatcher contract.

Run it with:   pytest -q /app/tests/test_contract.py

It intentionally FAILS against the buggy dispatcher that is shipped. Fix
dispatcher.py so every test here passes, then add your own stress/race tests.
"""

import asyncio
import sys

import pytest

sys.path.insert(0, "/app")
from dispatcher import Dispatcher, LeasePool


def run(coro):
    return asyncio.run(coro)


def job(d, state, n, delay=0.02, fail=False):
    """A tracked job: increments/decrements a live counter around its body."""

    async def _do():
        state["cur"] += 1
        state["peak"] = max(state["peak"], state["cur"])
        try:
            await asyncio.sleep(delay)
            if fail:
                raise RuntimeError(f"job {n} failed")
            return n * 10
        finally:
            state["cur"] -= 1

    return _do()


@pytest.mark.parametrize("limit", [1, 2, 3, 4, 8])
def test_concurrency_never_exceeds_cap(limit):
    def scenario():
        d = Dispatcher(limit)
        state = {"cur": 0, "peak": 0}
        n = limit * 3
        results = run(d.dispatch([job(d, state, i) for i in range(n)]))
        assert results == [i * 10 for i in range(n)]
        return state["peak"], d.leases.live

    for _ in range(5):
        peak, live = scenario()
        assert peak <= limit, (peak, limit)
        assert live == 0, live


def test_cleanup_on_failure():
    for limit in [1, 2, 4]:
        def scenario():
            d = Dispatcher(limit)
            n = limit * 3
            jobs = [job(d, {"cur": 0, "peak": 0}, i, fail=(i == 2 * limit))
                    for i in range(n)]
            try:
                run(d.dispatch(jobs))
                raise AssertionError("a job should have raised")
            except RuntimeError as e:
                assert "failed" in str(e)
            return d.leases.live

        for _ in range(5):
            assert scenario() == 0


@pytest.mark.parametrize("limit", [1, 2, 4])
@pytest.mark.parametrize("repeat", range(5))
def test_cleanup_when_dispatch_is_cancelled(limit, repeat):
    async def scenario_cancel():
        d = Dispatcher(limit)
        state = {"cur": 0, "peak": 0}
        n = limit * 3
        jobs = [job(d, state, i, delay=0.5) for i in range(n)]

        async def runner():
            return await d.dispatch(jobs)

        t = asyncio.create_task(runner())
        await asyncio.sleep(0.02)  # let some jobs start under the cap
        t.cancel()
        try:
            await t
            raise AssertionError("dispatch should have been cancelled")
        except asyncio.CancelledError:
            pass
        return d.leases.live

    assert run(scenario_cancel()) == 0