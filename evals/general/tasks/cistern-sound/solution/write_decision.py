#!/usr/bin/env python3
"""cistern-sound decision record writer (oracle).

Reads the shipped specification at /app/README.md, extracts the two
requirements that cannot both be satisfied (R4: raw gross figures; R7:
settled amounts), and writes /app/decisions.md quoting them verbatim along
with the adopted resolution. Reads only the shipped repository, never
/tests.
"""
import pathlib
import re

README = pathlib.Path("/app/README.md")
OUT = pathlib.Path("/app/decisions.md")

text = README.read_text(encoding="utf-8")


def paragraph(rid, nxt):
    m = re.search(r"(?ms)^%s\..*?(?=^%s\.)" % (rid, nxt), text)
    if not m:
        raise SystemExit("could not find requirement %s in README" % rid)
    return m.group(0).strip()


r4 = paragraph("R4", "R5")
r7 = paragraph("R7", "R8")

assert "no netting, deduction, or adjustment applied" in r4, "R4 phrase missing"
assert "a gross figure for such a group is misleading" in r7, "R7 phrase missing"

doc = f"""# Decision record - cistern-sound

## The conflict

Two requirements of the specification in `/app/README.md` cannot both hold
for a group that contains any refund or chargeback:

- **R4 (raw gross figures):** {r4}

- **R7 (settled amounts):** {r7}

Both are stated as flat rules with no exception clause. For any group whose
entries carry a refund or a chargeback, R4 demands the gross total (it
explicitly says the rule holds "regardless of refunds or chargebacks")
while R7 demands the settled total. The report emits exactly one total per
group, so the two requirements cannot both be satisfied at once.

The shipped code resolves the conflict ad hoc rather than by choosing a
rule: `paygate/policy.py` (commit "net refunded desks") nets only the
groups whose name mentions refunds or chargebacks. "Refunds desk" and
"Chargebacks team" are netted, while "Loyalty payouts" - which also
carries refunds - keeps its gross total because its name matches neither
hint. That is neither R4 nor R7 applied uniformly: it is a third,
name-dependent behaviour the specification never describes, and it makes
group totals non-comparable within a single report.

## Decision

Resolution: **every group is reported at its raw gross total (R4).**

Why R4 over R7:

- R4 is categorical: it applies "regardless of refunds or chargebacks", so
  it explicitly forecloses exactly the case R7 conditions on.
- The settled figure is recoverable by any reader (raw amounts and the
  refund/chargeback fields are all published in the ledger), whereas a
  settled-only report would make the gross figure unrecoverable.
- A single uniform rule keeps group totals comparable within one report,
  and satisfies R8 (grand total = sum of displayed group totals)
  trivially.

## Tests changed

- `paygate/tests/test_report.py`:
  - `test_refunds_desk_shows_settled` now asserts the gross total (125000).
  - `test_chargebacks_team_shows_settled` now asserts the gross total
    (70000).
  - `test_end_to_end` golden report updated: grand total 881027, GG02
    125000, GG03 70000, GG04 200000.
  - `test_loyalty_payouts_stays_gross` holds (gross is now the rule for
    every group, not a special case).
"""

OUT.write_text(doc, encoding="utf-8")
print("decisions.md written to %s" % OUT)