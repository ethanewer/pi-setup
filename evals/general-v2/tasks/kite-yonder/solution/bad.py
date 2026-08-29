#!/usr/bin/env python3
"""ctypes binding for the native pad routine (length-mismatch fixed).

Invokes bind_pad(buf, cap, n) from /app/bind/libbind.so, taking care to pass
the correct buffer length so the call neither overruns nor under-reads.
Exit 0 with stdout "ok" means the call succeeded and the bytes are right.
"""
import ctypes
import sys

lib = ctypes.CDLL("/app/bind/libpad.so")
lib.bind_pad.restype = ctypes.c_long
lib.bind_pad.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]

cap = 16
n = 18  # more than cap: the routine must clamp, never overflow
buf = ctypes.create_string_buffer(cap)
got = lib.bind_pad(ctypes.cast(buf, ctypes.c_void_p), cap, n)

exp = bytes((i * 37 + 11) & 0xFF for i in range(min(n, cap)))
ok = (got == min(n, cap)) and (bytes(buf[:cap])[:min(n, cap)] == exp)
print("ok" if ok else "BAD")
sys.exit(0 if ok else 1)