"""Group-total policy.

Resolution adopted for cistern-sound: every group is reported at its raw
gross total (spec R4). Refunds and chargebacks stay on the ledger for audit
and bookkeeping, but the displayed total never nets them and no group is
special-cased. See /app/decisions.md for the rationale.
"""


def group_total(group):
    """Return the total to display for *group* (a paygate.models.Group)."""
    return sum(entry.amount_cents for entry in group.entries)
