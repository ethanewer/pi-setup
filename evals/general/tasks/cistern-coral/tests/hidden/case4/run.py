#!/usr/bin/env python3
"""Hidden case 4 (C-API level): draw_flood rejection at the actual C boundary.

This case deliberately bypasses the pyvips Python binding and drives
libvips's own exported C entry point (vips_draw_flood1) directly through
ctypes. Its purpose is to make the regression immune to any patch at the
Python layer: a wrapper or monkeypatch in site-packages that raises from
pyvips cannot influence what the C library itself returns, so this case
scores the real behaviour of the compiled, installed libvips.

Expectations (independent of the upstream golden test, which uses pyvips
on a 100x100 image with starts at 200 and -1):

  * a 64x64 black uchar image, start point (200, 50) -- far past the right
    edge: must fail. vips_draw_flood1 must return -1 and the vips error
    buffer must say the start point is out of image.
  * start point (64, 62) -- exactly on the right boundary (x == width):
    must fail the same way.
  * start point (32, 32) -- in-bounds: must succeed (return 0) and the
    flood must paint every pixel of the uniform black region with the ink
    value.
"""
import ctypes
import sys

LIB = "/usr/local/lib/x86_64-linux-gnu/libvips.so.42"

lib = ctypes.CDLL(LIB)

# vips_image_new_from_memory_copy(data, size, width, height, bands, format)
# (VipsBandFormat enum: VIPS_FORMAT_UCHAR == 0 in this libvips)
UCHAR = 0
lib.vips_image_new_from_memory_copy.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int,
    ctypes.c_int, ctypes.c_int,
]
lib.vips_image_new_from_memory_copy.restype = ctypes.c_void_p
# int vips_draw_flood1(VipsImage *image, double ink, int x, int y, ...)
# optional named args are a NULL-terminated name/value list; we pass none,
# so the final argument is the NULL sentinel.
lib.vips_draw_flood1.argtypes = [
    ctypes.c_void_p, ctypes.c_double, ctypes.c_int, ctypes.c_int,
    ctypes.c_void_p,
]
lib.vips_draw_flood1.restype = ctypes.c_int
# vips_image_write_to_memory(image, &size) -> buffer or NULL
lib.vips_image_write_to_memory.argtypes = [
    ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
]
lib.vips_image_write_to_memory.restype = ctypes.c_void_p
lib.vips_error_buffer.restype = ctypes.c_char_p

W = 64
INK = 7

failures = 0


def make_black(width, height):
    pixels = (ctypes.c_ubyte * (width * height))()
    pixels[:] = bytes(width * height)
    im = lib.vips_image_new_from_memory_copy(
        ctypes.cast(pixels, ctypes.c_void_p), width * height,
        width, height, 1, UCHAR)
    if not im:
        raise RuntimeError("could not create test image at C level")
    return im


def flood(im, x, y):
    return lib.vips_draw_flood1(im, INK, x, y, None)


def err_text():
    buf = lib.vips_error_buffer()
    return ctypes.string_at(buf).decode(errors="replace") if buf else ""


# (a) far past the right edge -- must be rejected by the C library itself
im = make_black(W, W)
rc = flood(im, 200, 50)
err = err_text()
if rc == 0:
    print("case4: FAIL: C-level vips_draw_flood1 at (200, 50) returned 0 "
          "(silent success) on a 64x64 image")
    failures += 1
elif "out of image" not in err:
    print(f"case4: FAIL: C-level draw_flood at (200, 50) failed but error "
          f"does not say the start point is out of image: {err!r}")
    failures += 1
else:
    print("case4: ok: C-level (200, 50) rejected with 'start point out of image'")

# (b) exactly on the right boundary (x == width) -- must be rejected
im = make_black(W, W)
rc = flood(im, W, 62)
err = err_text()
if rc == 0:
    print(f"case4: FAIL: C-level vips_draw_flood1 at ({W}, 62) "
          "(x == width) returned 0 (silent success)")
    failures += 1
elif "out of image" not in err:
    print(f"case4: FAIL: C-level boundary start failed with wrong error: {err!r}")
    failures += 1
else:
    print(f"case4: ok: C-level ({W}, 62) boundary start rejected")

# (c) in-bounds start: succeeds and the uniform black region is all INK
im = make_black(W, W)
rc = flood(im, 32, 32)
if rc != 0:
    print("case4: FAIL: C-level vips_draw_flood1 at (32, 32) failed on a "
          f"valid start: {err_text()!r}")
    failures += 1
else:
    size = ctypes.c_size_t(0)
    data = lib.vips_image_write_to_memory(im, ctypes.byref(size))
    if not data or size.value != W * W:
        print(f"case4: FAIL: could not read back flood result (size={size.value})")
        failures += 1
    else:
        vals = ctypes.string_at(data, size.value)
        n_ink = sum(1 for v in vals if v == INK)
        if n_ink != W * W:
            print(f"case4: FAIL: full-region flood painted {n_ink}/{W*W} pixels "
                  f"at C level")
            failures += 1
        else:
            print(f"case4: ok: in-bounds C-level flood painted all {W*W} pixels")

if failures:
    print("case4: FAIL", file=sys.stderr)
    sys.exit(1)
print("case4: PASS")
sys.exit(0)