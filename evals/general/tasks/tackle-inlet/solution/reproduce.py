#!/usr/bin/env python3
"""The reproduction deliverable (/app/reproduce.py) as the oracle ships it.

Contract (see instruction.md): this script must exit 0 and print exactly one
line starting with "OK: empty string handled" when
`SnowballStemmer('hungarian').stem('')` really returns '' without raising;
it must exit non-zero when the bug is present (the uncaught IndexError or an
assertion failure). The verifier runs it twice: against a staged pristine
parent tree (must fail) and against the repaired tree (must pass).
"""

from nltk.stem.snowball import SnowballStemmer

stemmed = SnowballStemmer("hungarian").stem("")
assert stemmed == "", "hungarian stem('') returned %r instead of ''" % stemmed
print("OK: empty string handled")