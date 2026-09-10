"""statlib: summary helpers the avocet build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-2.0.0"


def variance(seq):
    """Sample variance, or None for degenerate input."""
    if len(seq) < 2:
        return None
    avg = sum(seq) / len(seq)
    return sum((x - avg) ** 2 for x in seq) / (len(seq) - 1)
