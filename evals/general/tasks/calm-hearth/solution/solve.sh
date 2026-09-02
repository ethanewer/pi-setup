#!/usr/bin/env bash
# calm-hearth oracle: fix the custom heap, rebuild it, and author every
# deliverable (/app/fixedheap, /app/callffi.py, /app/reimpl.py, /app/notes.md).
set -euo pipefail
cd /app

# ---------------------------------------------------------------------------
# 1) Fix the release-mode heap crash (the root cause is in user.cpp's
#    heap_free, which never returns a released block to the free list).
# ---------------------------------------------------------------------------
python3 - <<'PY'
src = open('user.cpp').read()
lines = src.split('\n')
patched = False
for i, ln in enumerate(lines):
    if '// <-- BUG' in ln or '(void)n' in ln:
        lines[i] = ('n->next = free_head;   // re-link the released block into the free list\n'
                    '    free_head = n;')
        patched = True
        break
if not patched:
    raise SystemExit('root-cause line not found in user.cpp')
open('user.cpp', 'w').write('\n'.join(lines))
print('user.cpp patched: heap_free now returns blocks to the free list')
PY

# ---------------------------------------------------------------------------
# 2) Rebuild the release binary /app/fixedheap from the fixed source.
# ---------------------------------------------------------------------------
make clean >/dev/null 2>&1 || true
make 2>&1 | tail -3
[ -x /app/fixedheap ] || { echo "fixedheap build failed"; exit 1; }

# sanity: the full-arena free/realloc sequence must no longer crash
ROOT=$(( (1 << 24) - 16 ))
printf 'A %d\nW 200\nF\nA %d\nW 55\n' "$ROOT" "$ROOT" > /tmp/chk.heap
out=$(/app/fixedheap /tmp/chk.heap)
[ "$out" = "HEAP-OK $(( ROOT * 55 ))" ] || { echo "fixedheap sanity failed: $out"; exit 1; }
echo "fixedheap sanity ok: $out"

# ---------------------------------------------------------------------------
# 3) /app/callffi.py - load the native library and invoke its exported 64-bit
#    transform across the correct FFI signature.
# ---------------------------------------------------------------------------
cat > /app/callffi.py <<'PY'
import sys, ctypes

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: callffi.py <input> <output>\n")
        return 2
    lib = ctypes.CDLL('/app/libtransform.so')
    fn = lib.scramble_hill
    fn.restype = ctypes.c_int64
    fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]

    with open(sys.argv[1], 'rb') as fh:
        data = fh.read()
    buf = (ctypes.c_uint8 * max(1, len(data)))()
    if data:
        ctypes.memmove(buf, data, len(data))
    ret = fn(buf, len(data))            # passes pointer; reads 64-bit signed
    out = bytes(buf[:len(data)])
    with open(sys.argv[2], 'wb') as fh:
        fh.write(out)
    print("FFI-RET %d" % ret)
    return 0

if __name__ == '__main__':
    sys.exit(main())
PY

# ---------------------------------------------------------------------------
# 4) /app/reimpl.py - reimplementation of the reverse-engineered native
#    target (a 3x3 low-pass convolution, divisor 16, replicated edges).
# ---------------------------------------------------------------------------
cat > /app/reimpl.py <<'PY'
import sys

K = [1, 2, 1, 2, 4, 2, 1, 2, 1]

def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: reimpl.py <grid>\n")
        return 2
    with open(sys.argv[1]) as fh:
        first = fh.readline().split()
        H, W = int(first[0]), int(first[1])
        g = [[int(x) & 0xff for x in fh.readline().split()] for _ in range(H)]
    for y in range(H):
        row = []
        for x in range(W):
            acc = 0
            for dy in range(3):
                sy = max(0, min(H - 1, y + dy - 1))
                for dx in range(3):
                    sx = max(0, min(W - 1, x + dx - 1))
                    acc += g[sy][sx] * K[dy * 3 + dx]
            row.append(str(acc // 16))
        print(' '.join(row))
    return 0

if __name__ == '__main__':
    sys.exit(main())
PY

# ---------------------------------------------------------------------------
# 5) /app/notes.md - document the root cause and the reverse-engineered op.
# ---------------------------------------------------------------------------
cat > /app/notes.md <<'MD'
# calm-hearth notes

## 1) Custom heap crash - root cause
`/app/user.cpp`'s `heap_free` never re-linked a released block back into the
free list (`free_head`). After a workload freed the whole arena and requested
it again, `heap_alloc` walked an empty list, returned NULL, and `main.cpp`'s
unconditional write into the returned pointer crashed (SIGSEGV) in the -O2
release build. Fix: re-insert the chunk - `n->next = free_head; free_head = n;`.

## 2) FFI call
`/app/libtransform.so` exports `scramble_hill(uint8_t *buf, size_t n) -> int64_t`.
`/app/callffi.py` uses ctypes with restype `c_int64` and argtypes
`(POINTER(c_uint8), c_size_t)`, passing a mutable buffer pointer and reading
the 64-bit signed sum of the in-place transformed bytes + 424242.

## 3) Reverse-engineered native target `/app/target/render`
The binary applies a 3x3 low-pass convolution (blur) to the input grid:
kernel [1 2 1; 2 4 2; 1 2 1], divisor 16 (integer floor division), and
replicated (clamped) edge handling. `/app/reimpl.py` reproduces it exactly.
MD

chmod +x /app/callffi.py /app/reimpl.py

# ---------------------------------------------------------------------------
# 6) Confirm the deliverables behave on spot checks.
# ---------------------------------------------------------------------------
printf '\x01\x02\x03' > /tmp/a.in
python3 /app/callffi.py /tmp/a.in /tmp/a.out | grep -q '^FFI-RET 424479$'
printf '3 3\n5 5 5\n5 5 5\n5 5 5\n' > /tmp/g.txt
[ "$(python3 /app/reimpl.py /tmp/g.txt)" = "$(/app/target/render /tmp/g.txt)" ] \
    || { echo "reimpl/render mismatch"; exit 1; }
echo "oracle complete: fixedheap+callffi.py+reimpl.py+notes.md are in /app"