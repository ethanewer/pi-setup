"""avocet: probe statistics for the observability service."""
from .core import mean, median, pct, bandwidth, jitter

__all__ = ["mean", "median", "pct", "bandwidth", "jitter"]
__version__ = "0.7.2"
