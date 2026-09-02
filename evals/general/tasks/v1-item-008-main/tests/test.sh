#!/bin/bash
mkdir -p /logs/verifier
reward=0

# --- 1) Independent behavioral verification of Dispatcher -----------------
behav_ok=0
if [ -f /app/dispatcher.py ] && python3 - <<'PYEOF'
import asyncio, sys
sys.path.insert(0, "/app")
from dispatcher import Dispatcher

def run(coro):
    return asyncio.run(coro)

def job(d, state, n, delay=0.02, fail=False):
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

# concurrency cap + ordering + full cleanup (repeated for race-sensitivity)
for limit in (1, 2, 3, 4, 8):
    for _ in range(5):
        d = Dispatcher(limit)
        st = {"cur": 0, "peak": 0}
        n = limit * 3
        res = run(d.dispatch([job(d, st, i) for i in range(n)]))
        assert res == [i * 10 for i in range(n)], (limit, res)
        assert st["peak"] <= limit, ("peak", limit, st["peak"])
        assert d.leases.live == 0, ("live", limit)
        assert st["cur"] == 0, ("cur", limit)

# cleanup on failure
for limit in (1, 2, 4):
    for _ in range(3):
        d = Dispatcher(limit)
        st = {"cur": 0, "peak": 0}
        n = limit * 3
        jobs = [job(d, st, i, fail=(i == 2 * limit)) for i in range(n)]
        try:
            run(d.dispatch(jobs))
            raise AssertionError("expected failure")
        except RuntimeError:
            pass
        assert d.leases.live == 0
        assert st["cur"] == 0

# cleanup on cancellation (race test, repeated)
for limit in (1, 2, 4):
    for _ in range(5):
        async def scenario():
            d = Dispatcher(limit)
            st = {"cur": 0, "peak": 0}
            n = limit * 3
            jobs = [job(d, st, i, delay=0.5) for i in range(n)]
            runner = asyncio.create_task(d.dispatch(jobs))
            await asyncio.sleep(0.02)
            runner.cancel()
            try:
                await runner
                raise AssertionError("should have been cancelled")
            except asyncio.CancelledError:
                pass
            return d.leases.live, st["cur"]
        live, cur = run(scenario())
        assert (live, cur) == (0, 0), (limit, live, cur)

behav_ok = 1
PYEOF
then
  behav_ok=1
fi

# --- 2) agent must have supplied /app/tests/test_behavior.py and the
#        provided /app/tests/test_contract.py must both pass under pytest ---
agent_ok=0
if [ -f /app/tests/test_behavior.py ] && [ -f /app/tests/test_contract.py ]; then
  if pytest -q /app/tests/ >/tmp/pytest_out.txt 2>&1; then
    agent_ok=1
  fi
fi

if [ "$behav_ok" = "1" ] && [ "$agent_ok" = "1" ]; then
  reward=1
elif [ "$behav_ok" = "1" ]; then
  reward=0.5
else
  reward=0
fi

echo "$reward" > /logs/verifier/reward.txt