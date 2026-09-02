"""relay-none beacon generator module (verification fixture)."""

SEED_LO = 1000
SEED_HI = 1400

PREFIX = "ZQ-"
SUFFIX = "-SPAR"


def beacon_code(seed):
    k = (seed * 65537) % 100000
    return "%s%05d%s" % (PREFIX, k, SUFFIX)
