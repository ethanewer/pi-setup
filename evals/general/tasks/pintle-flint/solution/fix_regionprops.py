#!/usr/bin/env python3
"""Apply the upstream fix for the regionprops cache-retention bug
(scikit-image/scikit-image#7333) to the checkout at /app/src.

The parent-tree _cached wrapper is:

    def _cached(f):
        @wraps(f)
        def wrapper(obj):
            cache = obj._cache
            prop = f.__name__

            if not ((prop in cache) and obj._cache_active):
                cache[prop] = f(obj)

            return cache[prop]

        return wrapper

i.e. the cache write is executed even when the cache is inactive, which is the
bug: with cache=False every computed property is stored into the object's
private stash.  The fix restructures the wrapper exactly as upstream did.

Usage: fix_regionprops.py /app/src/skimage/measure/_regionprops.py
"""

import sys
from pathlib import Path

OLD = """        if not ((prop in cache) and obj._cache_active):
            cache[prop] = f(obj)

        return cache[prop]"""

NEW = """        if not obj._cache_active:
            return f(obj)

        if prop not in cache:
            cache[prop] = f(obj)

        return cache[prop]"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: fix_regionprops.py <path to _regionprops.py>")
    path = Path(sys.argv[1])
    src = path.read_text()
    if OLD not in src:
        raise SystemExit("expected the pre-fix _cached body; not found in %s" % path)
    path.write_text(src.replace(OLD, NEW))
    print("patched %s" % path)


if __name__ == "__main__":
    main()