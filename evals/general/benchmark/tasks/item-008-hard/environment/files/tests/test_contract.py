"""Adversarial evaluator for the Dispatcher cleanup contract.

Run with:  pytest -q /app/tests/test_contract.py

This exposes a DOUBLE-RELEASE bug in dispatcher.py: on the abnormal/cancellation
path the LeasePool counter goes negative. Every test checks that the accounting
returns exactly to 0 (and never below 0) on normal, failure, and cancel paths.
"""

import asyncio
import sys

import pytest

sys.path.insert(0, "/app")
from dispatcher import Dispatcher, LeasePool


def run(coro):
    return asyncio.run(coro)


def job(state, n, delay=0.02, fail=False):
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
def test_concurrency_cap_and_normal_accounting(limit):
    for _ in range(5):
        d = Dispatcher(limit)
        st = {"cur": 0, "peak": 0}
        n = limit * 3
        res = run(d.dispatch([job(st, i) for i in range(n)]))
        assert res == [i * 10 for i in range(n)]
        assert st["peak"] <= limit, (limit, st["peak"])
        assert d.leases.live == 0, (limit, d.leases.live)
        assert st["cur"] == 0


def test_cleanup_on_failure_is_exact():
    for limit in (1, 2, 4):
        for _ in range(5):
            d = Dispatcher(limit)
            st = {"cur": 0, "peak": 0}
            n = limit * 3
            jobs = [job(st, i, fail=(i == 2 * limit)) for i in range(n)]
            try:
                run(d.dispatch(jobs))
                raise AssertionError("expected a failure")
            except RuntimeError:
                pass
            assert d.leases.live == 0, (limit, d.leases.live)
            assert d.leases.live >= 0
            assert st["cur"] == 0


@pytest.mark.parametrize("limit", [1, 2, 4])
@pytest.mark.parametrize("repeat", range(6))
def test_cancel_is_exact_and_never_negative(limit, repeat):
    async def scenario_cancel():
        d = Dispatcher(limit)
        st = {"cur": 0, "peak": 0}
        n = limit * 3
        jobs = [job(st, i, delay=0.4) for i in range(n)]
        runner = asyncio.create_task(d.dispatch(jobs))
        await asyncio.sleep(0.02)
        runner.cancel()
        try:
            await runner
            raise AssertionError("should have been cancelled")
        except asyncio.CancelledError:
            pass
        return d.leases.live, st["cur"]

    live, cur = run(scenario_cancel())
    assert live == 0, (limit, live)
    assert live >= 0
    assert cur == 0, (limit, cur)