import asyncio
from contextlib import asynccontextmanager


class LeasePool:
    """Tracks the number of concurrently-held 'lease' slots.

    Each dispatch job must hold exactly one lease for its whole lifetime and
    release it exactly once when it finishes, even if it raises or is cancelled.
    """

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
    """Runs a batch of coroutines under a concurrency cap.

    Contract (this class currently violates parts of it -- that is the bug to
    fix):

      * At most ``max_concurrency`` coroutines may be in flight at once.
      * Every job runs while holding exactly one lease; the lease is released
        when the job finishes, raises, OR is cancelled.
      * If any job raises, or if the enclosing dispatch task itself is
        cancelled, every not-yet-finished job is cancelled and *awaited* so
        that cleanup (lease release / semaphore give-back) actually runs before
        control returns. Nothing may be left running, and no lease may leak.
    """

    def __init__(self, max_concurrency: int):
        if not isinstance(max_concurrency, int) or max_concurrency < 1:
            raise ValueError("max_concurrency must be a positive int")
        self.max_concurrency = max_concurrency
        self._sem = asyncio.Semaphore(max_concurrency)
        self.leases = LeasePool()

    async def dispatch(self, coros):
        """Run all ``coros`` (coroutine objects) under the concurrency cap.

        Returns a list of their results in input order. Raises if any job
        raises (cancel and await the stragglers first). If dispatch itself is
        cancelled, cancels and awaits the stragglers, then propagates the
        cancellation.
        """
        # BROKEN implementation: spawns every coroutine unguarded (ignoring the
        # semaphore and the lease), and on failure/cancellation does not cancel
        # or await the pending jobs, so leases leak and cleanup never runs.
        tasks = [asyncio.create_task(coro) for coro in coros]
        return await asyncio.gather(*tasks)