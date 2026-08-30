#!/usr/bin/env python3
"""fern_gl: load the OSMesa offscreen runtime for this interpreter.

Two environment notes make this loader strict *on purpose*:

* It searches ONLY the directory list taken from the $FERN_GL_LIB environment
  variable (colon-separated, empty entries dropped) followed by the fixed
  location /opt/osp/gl/lib. It never falls back to ctypes.util.find_library or
  to ldconfig, so an unconfigured interpreter genuinely cannot load the
  library until the proper runtime is placed where this loader looks.
* When $FERN_GL_LIB names paths that do not exist, those entries are simply
  skipped and the loader still falls through to /opt/osp/gl/lib. A repairing
  agent must therefore tolerate (not crash on) a bogus/empty environment
  value while still finding the runtime in the standard place.

On success it prints OSMESA_OK and exits 0 (an offscreen render context was
created). Otherwise it prints OSMESA_FAIL and exits nonzero.
"""
import ctypes
import os
import sys

CANDIDATE_NAMES = ('libOSMesa.so', 'libOSMesa.so.6', 'libOSMesa.so.8')


def candidates():
    dirs = []
    env = os.environ.get('FERN_GL_LIB')
    if env:
        dirs += [d for d in env.split(':') if d]
    dirs += ['/opt/osp/gl/lib']
    return dirs


def find():
    for d in candidates():
        for name in CANDIDATE_NAMES:
            p = os.path.join(d, name)
            if os.path.isfile(p) and os.access(p, os.R_OK):
                return p
    return None


def main():
    path = find()
    if not path:
        print('OSMESA_FAIL no-mesa-in-search-path')
        return 2
    try:
        lib = ctypes.CDLL(path)
    except OSError as exc:
        print('OSMESA_FAIL load %s: %s' % (path, exc))
        return 3
    lib.OSMesaCreateContext.restype = ctypes.c_void_p
    lib.OSMesaCreateContext.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
    ctx = lib.OSMesaCreateContext(2, None)  # OSMESA_RGBA
    if ctypes.cast(ctx, ctypes.c_void_p).value:
        print('OSMESA_OK %s ctx=%s' % (path, ctx))
        return 0
    print('OSMESA_FAIL null-context')
    return 4


if __name__ == '__main__':
    sys.exit(main())