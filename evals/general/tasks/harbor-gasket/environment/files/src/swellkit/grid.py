"""Geodesy helpers for swellkit."""

import math

_EARTH_KM = 6371.0088

__all__ = ["haversine_km"]


def haversine_km(lon1, lat1, lon2, lat2):
    """Great-circle distance in kilometres between two lon/lat points.

    Arguments are decimal degrees; the standard haversine formula with mean
    earth radius 6371.0088 km is used. A point compared with itself yields 0.0.
    """
    p1 = math.radians(lat1)
    l1 = math.radians(lon1)
    p2 = math.radians(lat2)
    l2 = math.radians(lon2)
    dphi = p2 - p1
    dl = l2 - l1
    a = math.sin(dphi / 2.0) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2.0) ** 2
    return 2.0 * _EARTH_KM * math.asin(math.sqrt(a))
