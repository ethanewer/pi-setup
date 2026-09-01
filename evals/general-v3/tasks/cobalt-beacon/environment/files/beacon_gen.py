"""Cobalt channel beacon generator (attestation fixture).

A beacon code is derived deterministically from an integer seed. The
attestation station publishes one code per commissioned seed in the
half-open seed range [SEED_LO, SEED_HI).
"""

SEED_LO = 100
SEED_HI = 400

PREFIX = "CN-"
SUFFIX = "-RELAY"


def beacon_code(seed):
    """Return the beacon code string for an integer seed."""
    k = (seed * 7919) % 100000
    return "%s%05d%s" % (PREFIX, k, SUFFIX)
