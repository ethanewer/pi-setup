"""sndlib: audio-level helpers the wigeon build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-0.9.0"


def dbfs_to_linear(dbfs):
    """Map a dBFS reading in [-inf, 0] to a linear level in [0, 1]."""
    if dbfs >= 0:
        return 1.0
    return 10.0 ** (dbfs / 20.0)
