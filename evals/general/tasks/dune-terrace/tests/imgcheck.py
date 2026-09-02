#!/usr/bin/env python3
"""Image comparator for the dune-terrace verifier.

Usage:
  imgcheck.py target <agent> <golden> <ssim_min>
  imgcheck.py depth  <agent> <golden> <ssim_min> <tol> <frac_min>
  imgcheck.py color  <agent> <golden> <ssim_min>
  imgcheck.py icon   <png> <W> <H>
  imgcheck.py iconsame <png-a> <png-b>

The icon checks are *structural*: the prose does not fully fix the icon's
colors/positions/font raster, so byte-identity with an externally-stored
golden is not derivable.  Instead `icon` verifies the PNG itself is valid,
64x64, 8-bit RGB, decodes cleanly, and its pixels actually depict the described
"dune sunset" scene (a layered scene with a cool gradient sky, a bright sun
disc, warm rolling dune bands, and glyph-like ink in a lower band).  `iconsame`
verifies two consecutive runs are byte-identical, i.e. the generator is
deterministic (no timestamps / randomness / varying zlib).
"""
import struct
import sys
import zlib

import numpy as np


def ssim(a, b):
    """Mean SSIM over 8x8 non-overlapping luminance windows, scalar [0..1]."""
    h, w = a.shape
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    total, n = 0.0, 0
    for y in range(0, h - 7, 8):
        for x in range(0, w - 7, 8):
            wa = a[y:y + 8, x:x + 8].astype(float)
            wb = b[y:y + 8, x:x + 8].astype(float)
            ma, mb = wa.mean(), wb.mean()
            va = ((wa - ma) ** 2).sum()
            vb = ((wb - mb) ** 2).sum()
            cov = ((wa - ma) * (wb - mb)).sum()
            npx = wa.size
            va /= npx; vb /= npx; cov /= npx
            total += ((2 * ma * mb + c1) * (2 * cov + c2)) / \
                     ((ma * ma + mb * mb + c1) * (va + vb + c2))
            n += 1
    return total / n if n else 0.0


def read_ppm(p):
    import re
    d = open(p, 'rb').read()
    m = re.match(rb'P6\n(\d+) (\d+)\n(\d+)\n', d)
    if not m:
        raise ValueError('bad PPM header: ' + p)
    w, h, _ = map(int, m.groups())
    raw = d[m.end():]
    return h, w, raw


def read_pgm(p):
    import re
    d = open(p, 'rb').read()
    m = re.match(rb'P5\n(\d+) (\d+)\n(\d+)\n', d)
    if not m:
        raise ValueError('bad PGM header: ' + p)
    w, h, mx = map(int, m.groups())
    raw = d[m.end():]
    arr = np.frombuffer(raw, dtype=np.uint8).astype(np.float32)
    if len(arr) != w * h:
        raise ValueError('PGM size mismatch')
    return h, w, arr.reshape(h, w) / (mx / 255.0)


def luma(rgb):
    arr = np.frombuffer(rgb, dtype=np.uint8).astype(np.float32)
    a = arr.reshape(-1, 3)
    return (0.299 * a[:, 0] + 0.587 * a[:, 1] + 0.114 * a[:, 2]).astype(np.uint8)


def read_pfm(p):
    d = open(p, 'rb').read()
    import re
    m = re.match(rb'PF\n(\d+) (\d+)\n(-?[0-9.eE+-]+)\n', d)
    if not m:
        raise ValueError('bad PFM header: ' + p)
    w, h = int(m.group(1)), int(m.group(2))
    scale = float(m.group(3))
    raw = d[m.end():]
    if len(raw) != w * h * 3 * 4:
        raise ValueError('PFM data size mismatch')
    f = np.frombuffer(raw, dtype='<f4').astype(np.float32).reshape(h, w, 3)
    if scale < 0:
        f = f[::-1]              # bottom-up → top-down
    g = (0.299 * f[:, :, 0] + 0.587 * f[:, :, 1] + 0.114 * f[:, :, 2]) * 255.0
    g = np.clip(g, 0, 255).astype(np.uint8)
    return h, w, g


def parse_png(path):
    """Return (W, H, bitdepth, colortype, decoded RGB8 array) for a PNG."""
    d = open(path, 'rb').read()
    if d[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG')
    w, h = struct.unpack('>II', d[16:24])
    pos = 8
    ihdr = None
    idat = b''
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos + 4])[0]
        tag = d[pos + 4:pos + 8]
        data = d[pos + 8:pos + 8 + ln]
        if tag == b'IHDR':
            ihdr = data
        elif tag == b'IDAT':
            idat += data
        pos += 12 + ln
    if ihdr is None or not idat:
        raise ValueError('PNG missing IHDR/IDAT')
    bitdepth, colortype = ihdr[8], ihdr[9]
    if bitdepth != 8 or colortype != 2:
        raise ValueError('expected 8-bit RGB PNG (bitdepth=%d colortype=%d)' %
                         (bitdepth, colortype))
    raw = zlib.decompress(idat)
    stride = 1 + w * 3
    if len(raw) != h * stride:
        raise ValueError('PNG decompressed size mismatch')

    def paeth(a, b, c):
        pp = a + b - c
        pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
        if pa <= pb and pa <= pc:
            return a
        if pb <= pc:
            return b
        return c

    rows = []
    prev = bytearray(stride)
    p = 0
    for _y in range(h):
        ft = raw[p]; p += 1
        line = raw[p:p + stride - 1]; p += stride - 1
        out = bytearray(stride)
        for i in range(stride - 1):
            b = line[i]
            a = out[i - 3] if i >= 3 else 0
            pr = prev[i + 1]
            c = prev[i - 2] if i >= 3 else 0
            if ft == 0:
                v = b
            elif ft == 1:
                v = (b + a) & 255
            elif ft == 2:
                v = (b + pr) & 255
            elif ft == 3:
                v = (b + (a + pr) // 2) & 255
            elif ft == 4:
                v = (b + paeth(a, pr, c)) & 255
            else:
                raise ValueError('unsupported PNG filter %d' % ft)
            out[i + 1] = v
        rows.append(bytes(out[1:]))
        prev = out
    arr = np.frombuffer(b''.join(rows), dtype=np.uint8).reshape(h, w, 3)
    return w, h, bitdepth, colortype, arr


def check_icon(args):
    """icon <png> <W> <H>: valid RGB PNG of exact size depicting the scene."""
    ga = args[2]
    ew, eh = int(args[3]), int(args[4])
    w, h, bd, ct, arr = parse_png(ga)
    dims_ok = (w, h) == (ew, eh)
    if not dims_ok:
        print('icon dims=(%d,%d) expected (%d,%d)' % (w, h, ew, eh))
        print('FAIL: wrong icon dimensions')
        return False
    # gather metrics
    R = arr[:, :, 0].astype(np.int32); G = arr[:, :, 1].astype(np.int32)
    B = arr[:, :, 2].astype(np.int32)
    lum = 0.299 * R + 0.587 * G + 0.114 * B
    ncol = len(set(map(tuple, arr.reshape(-1, 3))))
    std = float(lum.std())
    bright = int((lum > 190).sum())
    warm = int(((R >= G) & (G >= B) & (R > 120)).sum())
    cool = int(((B > R + 15) & (B > 90)).sum())
    ink = 0
    for y in range(int(h * 0.32), int(h * 0.95)):
        med = np.median(arr[y], axis=0)
        dist = np.sqrt(((arr[y].astype(float) - med) ** 2).sum(1))
        ink += int((dist > 60).sum())

    checks = {
        'size 64x64': dims_ok,
        '8-bit RGB PNG': (bd == 8 and ct == 2),
        'distinct colours in [16,1200]': 16 <= ncol <= 1200,
        'luminance variation': std >= 12.0,
        'bright sun/specular present': bright >= 40,
        'warm dune bands present': warm >= 500,
        'cool gradient sky present': cool >= 25,
        'glyph-like text in lower band': ink >= 30,
    }
    ok = all(checks.values())
    print('icon dims=(%d,%d) colours=%d std=%.1f bright=%d warm=%d cool=%d ink=%d'
          % (w, h, ncol, std, bright, warm, cool, ink))
    for k, v in checks.items():
        print('  [%s] %s' % ('ok' if v else 'FAIL', k))
    print('PASS' if ok else 'FAIL')
    return ok


def check_iconsame(args):
    """iconsame <a> <b>: two runs must be byte-identical (determinism)."""
    a = open(args[2], 'rb').read()
    b = open(args[3], 'rb').read()
    ok = a == b
    print('determinism byte-identical=%s' % ok)
    print('PASS' if ok else 'FAIL')
    return ok


def main():
    mode = sys.argv[1]
    if mode == 'target':
        ga, gb = sys.argv[2], sys.argv[3]
        lo = float(sys.argv[4])
        ha, wa, ra = read_ppm(ga)
        hb, wb, rb = read_ppm(gb)
        assert (wa, ha) == (wb, hb), 'target dims differ'
        s = ssim(luma(ra).reshape(ha, wa), luma(rb).reshape(hb, wb))
        print('target ssim=%.4f' % s)
        ok = s >= lo
        print('PASS' if ok else 'FAIL')
        sys.exit(0 if ok else 1)
    if mode == 'color':
        ga, gb = sys.argv[2], sys.argv[3]
        lo = float(sys.argv[4])
        ha, wa, ra = read_pfm(ga)
        hb, wb, rb = read_pfm(gb)
        assert (wa, ha) == (wb, hb), 'dims differ'
        s = ssim(ra.reshape(ha, wa), rb.reshape(hb, wb))
        print('color ssim=%.4f' % s)
        ok = s >= lo
        print('PASS' if ok else 'FAIL')
        sys.exit(0 if ok else 1)
    if mode == 'depth':
        ga, gb = sys.argv[2], sys.argv[3]
        lo = float(sys.argv[4])
        tol = float(sys.argv[5])
        frac_min = float(sys.argv[6])
        ha, wa, ra = read_pgm(ga)
        hb, wb, rb = read_pgm(gb)
        assert (wa, ha) == (wb, hb), 'dims differ'
        s = ssim(ra, rb)
        diff = np.abs(ra - rb)
        frac = float((diff <= tol).mean())
        ok = (s >= lo) and (frac >= frac_min)
        print('depth ssim=%.4f frac(<=%.0f)=%.4f' % (s, tol, frac))
        print('PASS' if ok else 'FAIL')
        sys.exit(0 if ok else 1)
    if mode == 'icon':
        ok = check_icon(sys.argv)
        sys.exit(0 if ok else 1)
    if mode == 'iconsame':
        ok = check_iconsame(sys.argv)
        sys.exit(0 if ok else 1)
    if mode == 'dims':
        import re as _re
        ex_w, ex_h = int(sys.argv[5]), int(sys.argv[6])
        def hdr_wh(path, magic):
            m = _re.match(magic.encode() + br'\n(\d+) (\d+)\n',
                          open(path, 'rb').read())
            if not m:
                return None
            return int(m.group(1)), int(m.group(2))
        wppm = hdr_wh(sys.argv[2], 'P6')
        wpfm = hdr_wh(sys.argv[3], 'PF')
        wpgm = hdr_wh(sys.argv[4], 'P5')
        ok = (wppm == (ex_w, ex_h)) and \
             (wpfm == (ex_w, ex_h)) and (wpgm == (ex_w, ex_h))
        print('dims expected %dx%d ppm=%s pfm=%s pgm=%s' %
              (ex_w, ex_h, wppm, wpfm, wpgm))
        print('PASS' if ok else 'FAIL')
        sys.exit(0 if ok else 1)
    print('unknown mode'); sys.exit(1)


if __name__ == '__main__':
    main()