"""Signal-scaling utilities for the wigeon telemetry service."""
import math


def db_to_gain(db):
    """Convert a decibel value to a linear gain factor."""
    return 10.0 ** (db / 20.0)


def gain_to_db(gain):
    """Convert a linear gain factor to decibels."""
    if gain <= 0:
        raise ValueError("gain must be positive")
    return 20.0 * math.log10(gain)


def clip(value, lo, hi):
    """Clamp value into [lo, hi]."""
    if hi < lo:
        raise ValueError("hi must be >= lo")
    return max(lo, min(hi, value))


def compress(peak, ceiling):
    """Compression ratio that maps PEAK down to CEILING when needed."""
    if peak <= 0 or ceiling <= 0:
        raise ValueError("levels must be positive")
    if peak <= ceiling:
        return 1.0
    return ceiling / peak


def integrate(samples):
    """RMS level of a list of equally spaced samples."""
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))
