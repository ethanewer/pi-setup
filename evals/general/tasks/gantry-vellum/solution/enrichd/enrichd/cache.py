"""Profile cache.

The enrichment engine consults this cache for a client's daily behaviour
digest before computing it, so repeated events avoid the costly digest fold.
Digests are pure functions of the normalised client identifier and the day,
so the cache is a strict memoisation: it can be sized, evicted or dropped
without changing a single output byte.
"""
from .embed import build_digest
from . import protocol

normalise_client = protocol.normalise_client


class ProfileCache:
    """Memoisation of daily behaviour digests.

    One entry per canonical (client, day) pair: the wire spelling of a client
    (casing, padding, collector tag) is normalised before it is used as a key,
    so every spelling of the same client shares one entry.  A cache hit is a
    plain dict lookup; a miss computes the digest (a pure function) and
    stores it.  Hits and misses are counted for observability.
    """

    def __init__(self, max_entries=None):
        self._digests = {}
        self._order = []
        self.max_entries = max_entries
        self.hits = 0
        self.misses = 0

    def __len__(self):
        return len(self._digests)

    def fetch(self, client, day):
        """Return the digest for (client, day), building and storing it if absent.

        The entry is keyed by the canonical (normalised) client and the day,
        mirroring how the digest itself is computed.
        """
        key = (normalise_client(client), day)
        digest = self._digests.get(key)
        if digest is None:
            self.misses += 1
            digest = build_digest(key[0], day)
            if self.max_entries is not None and len(self._digests) >= self.max_entries:
                self._evict_one()
            self._digests[key] = digest
            self._order.append(key)
        else:
            self.hits += 1
        return digest

    def _evict_one(self):
        """Drop the oldest entry (FIFO).  Safe: entries are pure functions."""
        if self._order:
            oldest = self._order.pop(0)
            self._digests.pop(oldest, None)
