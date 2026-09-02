"""legacy_normalize.py — the ORIGINAL (buggy) header-name normalizer that the
Velvet Ember Relay used to import.

Read this to understand the defect being fixed; then write your HARDENED
replacement in /app/normalize.py.  Do NOT modify or import this module.

Defects this shipped with (CWE-113, header injection / request splitting):
    * It never rejects control characters.  A header name containing CR, LF
      or NUL is passed straight through, letting an attacker close the current
    header line and splice arbitrary headers onto upstream requests.
    * It lowercases the WHOLE name instead of emitting the canonical title
      form, so 'content-type' came out as 'content-type' instead of
      'Content-Type' (downstream matching silently broke).
"""

def legacy_canonical(name):            # the BUGGY behaviour (never use)
    if not isinstance(name, str):
        name = str(name)
    return name.strip().lower()
    # defect: no control-character rejection, no canonical title form
