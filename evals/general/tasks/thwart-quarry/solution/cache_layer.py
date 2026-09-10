"""thwart-quarry reference cache layer.

Implements the contract from instruction.md:
  open_cache(host, port)                -> handle (handle.client is a redis.Redis)
  cached_get(handle, key, backend, ttl) -> str, single-flight stampede protected
  spend(handle, key, amount)            -> bool, one atomic server-side Lua EVAL

The layer is the real deliverable: cache-aside reads with TTL, a per-key
in-process lock implementing single-flight (only the first concurrent miss for
a key performs the backend fetch; the others wait and reuse the cached value),
and the compound read-modify-write as a registered Lua script so concurrent
spends can neither overdraw the balance nor lose an update.
"""
import threading

import redis


class _Handle(object):
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.client = redis.Redis(host=host, port=port, decode_responses=True)
        self.client.ping()
        self._guard = threading.Lock()
        self._locks = {}
        self._spend_script = None

    def _lock_for(self, key):
        with self._guard:
            lock = self._locks.get(key)
            if lock is None:
                lock = threading.Lock()
                self._locks[key] = lock
            return lock

    def cached_get(self, key, backend, ttl_seconds):
        # Fast path: cache hit.
        value = self.client.get(key)
        if value is not None:
            return value
        # Miss: single-flight. Exactly one caller per key performs the
        # backend fetch; the rest block here and then find the fresh value.
        lock = self._lock_for(key)
        with lock:
            value = self.client.get(key)
            if value is not None:
                return value
            value = backend.get(key)
            self.client.set(key, value, ex=int(ttl_seconds))
            return value

    def spend(self, key, amount):
        script = self._spend_script
        if script is None:
            body = (
                "local cur = tonumber(redis.call('GET', KEYS[1]) or '0')\n"
                "local amt = tonumber(ARGV[1])\n"
                "if cur and cur >= amt then\n"
                "  redis.call('SET', KEYS[1], cur - amt)\n"
                "  return 1\n"
                "end\n"
                "return 0\n"
            )
            script = self.client.register_script(body)
            self._spend_script = script
        return bool(script(keys=[key], args=[amount]))


def open_cache(host="127.0.0.1", port=6379):
    return _Handle(host, port)


def cached_get(handle, key, backend, ttl_seconds):
    return handle.cached_get(key, backend, ttl_seconds)


def spend(handle, key, amount):
    return handle.spend(key, amount)