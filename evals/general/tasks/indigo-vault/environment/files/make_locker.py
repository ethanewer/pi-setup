"""Mint the visible indigo-vault fixtures deterministically at build time.

Produces (under /app):
  - wordlist.txt   candidate passphrases, one per line (contains the true one)
  - passwd.hash    lowercase sha256 hex digest of the true passphrase
  - locker.zip     ZipCrypto-encrypted archive holding the release notes
"""
import hashlib
import os

from zipcrypto import write_encrypted_zip

APP = os.path.dirname(os.path.abspath(__file__))

BASE_WORDS = [
    "anchor", "atlas", "basalt", "beacon", "birch", "breeze", "brine",
    "cadence", "cairn", "candle", "cedar", "chalk", "cinder", "citadel",
    "cleat", "cobalt", "compass", "coral", "cumulus", "dagger", "delta",
    "dockyard", "drift", "ember", "estuary", "fathom", "ferry", "flint",
    "fresnel", "gantry", "geyser", "granite", "guyot", "harbor", "harrow",
    "hazel", "hearth", "helix", "hull", "indigo", "inlet", "jetty",
    "jib", "kelp", "keystone", "lagoon", "lantern", "lattice", "ledge",
    "lighthouse", "linen", "magnet", "manta", "marlin", "masonry", "mesa",
    "mooring", "moraine", "muzzle", "nimbus", "north", "oarsman", "onyx",
    "opal", "orchard", "paddle", "patch", "pelican", "pier", "pivot",
    "plank", "pond", "porthole", "prism", "pylon", "quarry", "quill",
    "raft", "reef", "relay", "ridge", "rigging", "river", "rope",
    "rudder", "sable", "saffron", "salvage", "sandbar", "scaffold", "sextant",
    "shadow", "shoal", "slate", "spar", "spindrift", "stack", "storm",
    "surf", "tidegate", "timber", "tundra", "turbine", "valve", "vellum",
    "vessel", "vine", "wake", "warf", "wharf", "winch", "yonder",
    "zephyr",
]

PASSWORD = "tidegate-9"

MEMBER_NAME = "release_notes.txt"
MEMBER_DATA = (
    "indigo locker\n"
    "artifact=release-2031.4\n"
    "signed-by=build-farm-3\n"
    "code=AX-2210\n"
).encode()


def build_wordlist():
    words = []
    for w in BASE_WORDS:
        words.append(w)
        for s in range(10):
            words.append("%s-%d" % (w, s))
    assert PASSWORD in words
    return words


def main():
    words = build_wordlist()
    with open(os.path.join(APP, "wordlist.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(words) + "\n")

    digest = hashlib.sha256(PASSWORD.encode()).hexdigest()
    with open(os.path.join(APP, "passwd.hash"), "w", encoding="utf-8") as fh:
        fh.write(digest + "\n")

    write_encrypted_zip(
        os.path.join(APP, "locker.zip"), PASSWORD,
        [(MEMBER_NAME, MEMBER_DATA)],
    )
    print("fixtures minted: wordlist=%d words, hash=%s" % (len(words), digest))


if __name__ == "__main__":
    main()
