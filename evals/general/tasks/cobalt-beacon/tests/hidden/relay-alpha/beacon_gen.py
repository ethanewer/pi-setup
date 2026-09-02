"""relay-alpha beacon generator module (verification fixture)."""

SEED_LO = 0
SEED_HI = 250

PREFIX = "VR-"
SUFFIX = "-PYLON"


def beacon_code(seed):
    k = (seed * 104729) % 100000
    return "%s%05d%s" % (PREFIX, k, SUFFIX)
