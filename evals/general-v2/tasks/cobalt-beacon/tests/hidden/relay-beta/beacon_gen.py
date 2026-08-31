"""relay-beta beacon generator module (verification fixture)."""

SEED_LO = 500
SEED_HI = 900

PREFIX = "AUX-"
SUFFIX = "-NODE"


def beacon_code(seed):
    k = (seed * 31 + 17) % 100000
    return "%s%05d%s" % (PREFIX, k, SUFFIX)
