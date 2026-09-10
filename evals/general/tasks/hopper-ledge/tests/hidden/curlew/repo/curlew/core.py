"""Geohash-style grid encoding for the curlew fleet tracker.

Cells are compact 32-char alphabet strings; latitude/longitude bits are
interleaved starting with longitude, which keeps nearby points in nearby
cells regardless of hemisphere.
"""

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"


def encode(lat, lon, precision=6):
    """Encode (lat, lon) into a grid cell string of PRECISION chars."""
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        raise ValueError("coordinates out of range")
    lat_min, lat_max = -90.0, 90.0
    lon_min, lon_max = -180.0, 180.0
    out = []
    bits, chunk, lat_turn = 0, 0, False
    while len(out) < precision:
        if not lat_turn:
            mid = (lon_min + lon_max) / 2.0
            if lon >= mid:
                chunk = (chunk << 1) | 1
                lon_min = mid
            else:
                chunk <<= 1
                lon_max = mid
        else:
            mid = (lat_min + lat_max) / 2.0
            if lat >= mid:
                chunk = (chunk << 1) | 1
                lat_min = mid
            else:
                chunk <<= 1
                lat_max = mid
        lat_turn = not lat_turn
        bits += 1
        if bits % 5 == 0:
            out.append(_BASE32[chunk])
            bits, chunk = 0, 0
    return "".join(out)


def neighbouring(cell):
    """The alphabet-adjacent cells for a valid cell string."""
    if not cell or any(c not in _BASE32 for c in cell):
        raise ValueError("invalid cell string")
    return set(cell[:-1] + c for c in _BASE32 if c != cell[-1])
