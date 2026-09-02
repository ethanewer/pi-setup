#!/bin/bash
# Oracle for moss-forge: apply the correct allocator fix to forge.c, rebuild
# the release binary, and sanity-run it on the visible workload.
# Never reads /tests.
set -eu

# The shipped bug: when a free block is split, the remainder's free-list link
# (rem->next) is never written, so it inherits stale payload bytes; the next
# allocation that walks past the remainder dereferences that garbage. Fix:
# splice the remainder in properly.
python3 - <<'PY'
src = open('/app/forge.c').read()
needle = """                Block *rem = (Block *)((unsigned char *)b + BLOCK_HDR + n);
                rem->size = b->size - n - BLOCK_HDR;
                b->size = n;"""
replacement = """                Block *rem = (Block *)((unsigned char *)b + BLOCK_HDR + n);
                rem->size = b->size - n - BLOCK_HDR;
                rem->next = b->next; /* link the remainder into the free list */
                b->size = n;"""
assert needle in src, "expected buggy split branch not found"
open('/app/forge.c', 'w').write(src.replace(needle, replacement, 1))
PY

make -C /app clean >/dev/null
make -C /app

# sanity: the visible workload must now run clean
/app/forgebench /app/workload.txt

echo "solve.sh done -> /app/forge.c fixed, /app/forgebench rebuilt"
ls -l /app/forge.c /app/forgebench
