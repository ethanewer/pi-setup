"""wigeon: sound scaling utilities for telemetry."""
from .core import db_to_gain, gain_to_db, clip, compress, integrate

__all__ = ["db_to_gain", "gain_to_db", "clip", "compress", "integrate"]
__version__ = "2.1.0"
