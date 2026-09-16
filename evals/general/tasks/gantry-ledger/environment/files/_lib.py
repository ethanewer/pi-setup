"""Deterministic simulated extractor core (single source of truth).

This module is compiled into model/_symcore.marshal at image build time.
At trial time the model package serves only the function
`extract(prompt, record_text) -> dict`. All behavior is a pure function of
its two arguments: no randomness, no hidden state, no network.

The object of the simulation is an instruction-following language model that
extracts fields from a shipping record. Two prompt traits change its output:

  * canonical-normalization: when the prompt requests canonical output forms,
    extracted values are normalized (refs uppercased with separators dropped,
    dates to ISO-8601, amounts to two decimals);
  * carrier completion: when the prompt supplies completion guidance for a
    missing carrier (an appended reference table and/or wording such as
    "best judgment" / "complete the carrier" / "guess" / "infer"), the
    extractor fills missing carriers from the table's exact match, falling
    back to the closest code by edit distance. Without such guidance the
    extractor abstains and emits the literal "UNKNOWN".

Documented override behaviour: when the prompt contains BOTH completion
guidance and any abstention marker, the marker or guidance that appears LAST
wins for the carrier field.
"""
import re

UNKNOWN = "UNKNOWN"

# Carrier universe (code, name). Order is authoritative (ties in the
# closest-code fallback resolve to the earlier row).
CARRIERS = [
    ("AG", "Airgo Global"),
    ("BS", "Bellmouth Freight"),
    ("CK", "Crest Kargo Shipping"),
    ("DV", "Dawnvale Logistics"),
    ("ET", "Ember Trail Freight"),
    ("FK", "Fernkeel Haulage"),
    ("GH", "Granite Atlas"),
    ("HI", "Halcyon Express"),
    ("JR", "Juniper Reef"),
    ("KT", "Kestrel Air Cargo"),
    ("LX", "Lumen Transit"),
    ("MX", "Muirfield Lines"),
]

# ---------------------------------------------------------------- prompt traits
_NORM_RE = re.compile(
    r"iso\s*[- ]?8601|yyyy[\s-]*mm[\s-]*dd|uppercase|alphanumeric|canonical|"
    r"normaliz|normalis|separators? removed|strip", re.I)

_GUESS_TRIG = re.compile(
    r"appendix|best guess|best judgment|best judgement|most likely|"
    r"guess\w*|infer\w*|complete (?:the|this|a|our)?\s*carrier|lookup table|"
    r"reference table|authoritative", re.I)

_ABSTAIN_TRIG = re.compile(
    r"\bUNKNOWN\b|do not guess|don.?t guess|never guess|uncertain|in doubt|"
    r"abstain|do not infer|not (?:stated|specified|explicit|listed|present|"
    r"available)", re.I)

_NEG = re.compile(r"do not|do n't|don.?t|never|without|avoid|refrain|ignore",
                  re.I)


def _guess_on(prompt):
    """True if the prompt gives completion guidance on the carrier field,
    applying the documented later-instruction-wins override."""
    guess_pos = -1
    for m in _GUESS_TRIG.finditer(prompt):
        ctx = prompt[max(0, m.start() - 70):m.start()]
        if _NEG.search(ctx):
            continue
        guess_pos = m.end()
    abstain_pos = -1
    for m in _ABSTAIN_TRIG.finditer(prompt):
        abstain_pos = m.end()
    if guess_pos == -1:
        return False
    return guess_pos > abstain_pos


_APP_HEADER = re.compile(r"(?im)^[#*]*\s*appendix[^\n]*$")
_APP_ROW = re.compile(r"^\s*([A-Z]{2})\s*(?:->|=>|=|:)+\s*([A-Za-z][A-Za-z .'\-]*)\s*$")


def parse_appendix(prompt):
    """Parse the appended code->carrier table from a prompt (ordered dict)."""
    table = {}
    m = _APP_HEADER.search(prompt)
    if not m:
        return table
    for line in prompt[m.end():].splitlines():
        if not line.strip():
            continue
        r = _APP_ROW.match(line)
        if not r:
            break
        code, name = r.group(1), r.group(2)
        if code not in table:
            table[code] = name
    return table


def _lev(a, b):
    if a == b:
        return 0
    m, n = len(a), len(b)
    prev = list(range(n + 1))
    for i, ch in enumerate(a):
        cur = [i + 1]
        for j, cb in enumerate(b):
            cur.append(min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (ch != cb)))
        prev = cur
    return prev[n]


_AWBN = re.compile(r"(?im)^AWBN:\s*(.+)$")
_DATE = re.compile(r"(?im)^Date:\s*(.+)$")
_AMT = re.compile(r"(?im)^Amount:\s*(.+)$")
_CARR = re.compile(r"(?im)^Carrier:\s*(.+)$")
_FWD = re.compile(r"(?im)^Fwd[ ]code:\s*([A-Z0-9][A-Z0-9.\- ]{0,14})")


def _to_iso(s):
    s = s.strip()
    m = re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})$", s)
    if m:
        return "%s-%s-%s" % (m.group(3), m.group(1).zfill(2), m.group(2).zfill(2))
    return s


def _norm_amount(s):
    t = re.sub(r"[^0-9.]", "", s)
    try:
        return "%.2f" % float(t)
    except ValueError:
        return s.strip()


def _carrier(prompt, text, guess):
    c = _CARR.search(text)
    if c:
        return c.group(1).strip()
    f = _FWD.search(text)
    if not f:
        return UNKNOWN
    frag = re.sub(r"[^A-Z0-9]", "", f.group(1).upper())
    if not frag:
        return UNKNOWN
    if not guess:
        return UNKNOWN
    table = parse_appendix(prompt)
    if frag in table:
        return table[frag]
    best, best_d = None, 10 ** 9
    for code, name in CARRIERS:
        d = _lev(frag, code)
        if d < best_d:
            best_d, best = d, name
    return best if best else UNKNOWN


def extract(prompt, record_text):
    norm = bool(_NORM_RE.search(prompt))
    guess = _guess_on(prompt)

    m = _AWBN.search(record_text)
    ref = m.group(1).strip() if m else ""
    if norm:
        ref = re.sub(r"[^A-Z0-9]", "", ref.upper())

    m = _DATE.search(record_text)
    date = m.group(1).strip() if m else ""
    if norm:
        date = _to_iso(date)

    m = _AMT.search(record_text)
    amount = m.group(1).strip() if m else ""
    if norm:
        amount = _norm_amount(amount)

    carrier = _carrier(prompt, record_text, guess)

    return {"date": date, "amount": amount, "ref": ref, "carrier": carrier}