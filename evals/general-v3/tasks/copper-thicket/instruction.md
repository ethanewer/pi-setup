# Reconcile Directory Exports into a Conflict Report

You are the data-steward on duty for **Meridian Analytics**, a fictional B2B
software vendor. Two internal systems export the employee directory
independently: the **CRM** (`/app/crm_export.json`) and the **billing
platform** (`/app/billing_export.json`). The two exports routinely disagree.
Your job is to build a reusable reconciliation program that diffs the exports
per user and per field, picks a winner using the company precedence policy,
and emits a structured conflict report.

The verifier re-runs your program **unchanged** on brand-new exports that
follow the same contract, so it must be correct on any conforming input, not
just the provided fixtures.

## Environment

- Working directory: `/app`. It already contains the two input files
  `/app/crm_export.json` and `/app/billing_export.json`. Python 3.12 is
  available as `python3` (standard library only; no network).
- **Do not modify `/app/crm_export.json` or `/app/billing_export.json`.**

## Input format

Each input file is a JSON object mapping user id → record, where a record is a
JSON object mapping field name → value. Values are JSON strings, JSON `null`
(an absent value), or the field may be missing entirely. Example:

```json
{
  "u-100": {"email": "ada@meridian.example", "phone": "555-0101", "title": "Engineer"},
  "u-200": {"email": null, "title": "  Designer ", "location": "LDN"}
}
```

- User ids and field names are compared exactly (case-sensitive).
- Only these **five canonical fields** participate in reconciliation:
  `email`, `phone`, `title`, `department`, `manager`. Any other field in a
  record is ignored completely.
- A value is **present** for reconciliation when it is a JSON string whose
  content after stripping leading/trailing whitespace is non-empty. JSON
  `null`, a missing key, or a string that is empty (or only whitespace) all
  count as **absent**.
- For comparison (and for reporting), a present value is used **after**
  stripping leading/trailing whitespace. Comparison is case-sensitive and
  exact otherwise (`"Designer"` vs `"designer"` is a conflict).

## Reconciliation semantics (implement exactly)

For each user and each canonical field:

- The **winner** (chosen value) is decided by per-field precedence between the
  two systems:
  - CRM wins for: `title`, `department`, `manager`
  - Billing wins for: `email`, `phone`
  - If the winning system's value is absent but the other system's value is
    present, the other system's value is the chosen value.
- A **conflict** exists for a `(user, field)` pair if and only if **both**
  systems have a present value for that pair **and** the trimmed values
  differ. Pairs where either side is absent, or where both sides agree after
  trimming, are **not** conflicts and must not appear in the report.

## Deliverables (both required)

1. `/app/reconcile.py` — a runnable Python program:
   ```
   python3 /app/reconcile.py <crm.json> <billing.json> <output.json>
   ```
   It reads the two exports and writes the conflict report JSON to
   `<output.json>`. It must work on any exports conforming to the contract
   above (including files that are empty objects).

2. `/app/conflict_report.json` — the report your program produces for the
   provided fixtures:
   ```
   python3 /app/reconcile.py /app/crm_export.json /app/billing_export.json /app/conflict_report.json
   ```

## Report schema (exact)

The output must be a valid JSON object with exactly these keys:

```json
{
  "total_conflicts": <int>,
  "conflicts": [
    {
      "user": "<user id>",
      "field": "<canonical field>",
      "values": [
        {"system": "crm", "value": "<trimmed value or null>"},
        {"system": "billing", "value": "<trimmed value or null>"}
      ],
      "winner": "<chosen value>",
      "winner_source": "<\"crm\" or \"billing\">"
    }
  ]
}
```

- `conflicts` contains **every** conflicting `(user, field)` pair. Ordering:
  users in ascending lexicographic order of user id; within a user, fields in
  this fixed order: `email`, `phone`, `title`, `department`, `manager`.
- `values` always lists the crm entry first, then the billing entry. Since a
  conflict requires both sides present, both entries carry the trimmed
  string values of each side.
- `winner` is the chosen (trimmed) value under the precedence rules above.
- `winner_source` is `"crm"` or `"billing"` — the system the winner came from.
- `total_conflicts` must equal exactly `len(conflicts)`.
- If there are no conflicts: `{"total_conflicts": 0, "conflicts": []}`.

## Edge cases probed by the grader's hidden inputs

- Users present in only one export (never conflicts).
- `null`, missing keys, empty-string, and whitespace-only values (absent).
- Values equal after trimming (not a conflict) vs differing only in case
  (a conflict).
- Extra non-canonical fields that must be ignored.
- Both exports empty objects → `{"total_conflicts": 0, "conflicts": []}`.

## Constraints

- Standard library only; no network access.
- Do not hard-code to the provided fixture contents or filenames beyond the
  documented command-line interface.
- Do not modify the fixtures in `/app`.
