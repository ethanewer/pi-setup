import asyncio
from contextlib import asynccontextmanager


class LeasePool:
    """Counts concurrently-held lease slots. Must return to 0 after every batch.

    ``hold()`` is a self-correcting async context manager: it increments on
    entry and decrements exactly once on exit, even if the body raises or is
    cancelled.
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
    """Runs a batch of coroutines under a concurrency cap with per-job leases.

    Contract:

      * at most ``max_concurrency`` jobs run at once,
      * each job holds exactly one lease for its whole lifetime,
      * a lease is returned exactly once whether the job succeeds, raises, or
        is cancelled,
      * on a job failure or when the dispatch task is cancelled, the pending
        stragglers are cancelled and awaited so their cleanup runs, then the
        original error / cancellation is re-raised,
      * ``self.leases.live`` is ``0`` after dispatch returns or raises, and
        never goes negative.
    """

    def __init__(self, max_concurrency: int):
        if not isinstance(max_concurrency, int) or max_concurrency < 1:
            raise ValueError("max_concurrency must be a positive int")
        self.max_concurrency = max_concurrency
        self.leases = LeasePool()

    async def _guarded(self, coro):
        async with self._sem:
            async with self.leases.hold():
                try:
                    return await coro
                except BaseException as exc:
                    # BUG (to fix): this is a *spurious* second release of the
                    # same lease on the abnormal-path only. lease.hold() already
                    # decrements once in its ``finally``, so a job that ends by
                    # raising or being cancelled decrements the lease counter
                    # twice: live goes NEGATIVE. Normal jobs look fine; only
                    # error/cancel paths reveal it.
                    self.leases._live -= 1
                    raise

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