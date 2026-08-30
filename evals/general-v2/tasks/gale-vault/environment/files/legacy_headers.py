"""legacy_headers.py — the ORIGINAL (v2, buggy) header canonicalizer in the
downstream "flagstone" service that Gale Vault used to import.

Read this reference to learn the canonical form the service must emit, then
write your HARDENED replacement function ``canonical_header`` inside
``/app/api.py``.  This module is intentionally left BUGGY, exactly as the 
legacy one was; do not build against it.

Defects this shipped with (CWE-113, HTTP response splitting / header injection):
    * It never rejects control characters.  A header name like
      "x\\nX:\\rfoo: 1" is folded into the outgoing header with CR/LF intact,
      closing the current header line and splicing attacker-controlled
      headers/response bytes onto it.
    * It silently returns "" for an empty / non-string name instead of raising.

Over-broad hardening is just as wrong: rejecting every control-character-free
name, or mangling the canonical title-case of benign inputs, breaks the valid
case.  Your hardened implementation must do BOTH:

  1. raise ValueError on any name that is not a non-empty string OR that
     contains a control character (ord(c) < 0x20 or ord(c) == 0x7f);
  2. otherwise return the canonical title form:
       canonical('content-type')    -> 'Content-Type'
       canonical('Accept')          -> 'Accept'
       canonical('x-note-id')       -> 'X-Note-Id'
       canonical('cache-control')   -> 'Cache-Control'
       canonical('x-Custom-Header') -> 'X-Custom-Header'
     i.e. split on '-', uppercase the first letter and lowercase the rest of
     each non-empty token, rejoin with '-'.
"""

def legacy_canonical(name):            # the v1 BUGGY behaviour (never use)
    if not isinstance(name, str):
        name = str(name)
    if not name:
        return ""                       # defect #2: empty passes silently
    return "-".join(t[:1].upper() + t[1:].lower() for t in name.split("-"))
    # defect #1: control characters are never rejected