# Fume Wheel — Deneb Slip Cooperative claims adjudication

The **Deneb Slip Cooperative** reimburses mooring, buoy, and haul-out claims
from its member slips. You are building the claims adjudication
engine — a deterministic, integer-cents pipeline — plus the adjudication
report for the visible fixtures. This is a pure-stdlib Python task: **no
network, no third-party packages** (the `datetime`, `json`, `sys` modules
suffice).

## Fixtures already in `/app` (read-only)

- `/app/policy.json` — the coverage policy, with exactly these keys:
  `currency` (informational string only, never used in arithmetic),
  `policy_start` / `policy_end` (ISO `YYYY-MM-DD`, inclusive window),
  `deductible_cents`, `coinsurance_percent` (integer, 0–100),
  `per_claim_cap_cents`, `annual_aggregate_cap_cents` (all non-negative
  integers), and `excluded_categories` (a JSON array of category strings).
- `/app/claims.jsonl` — one claim per line, each line a JSON object with
  `id` (string), `date` (ISO `YYYY-MM-DD`), `category` (string),
  `amount_cents` (non-negative integer), `reference` (informational string).
  Blank lines are ignored. All dates are valid ISO calendar dates.

## Deliverables

1. `/app/adjudicate.py` — the engine. CLI:
   ```
   python3 /app/adjudicate.py <policy.json> <claims.jsonl> <out.json>
   ```
   Exit code 0 on success (writing `<out.json>`); exit nonzero with a
   message on stderr if an input cannot be read/parsed.
2. `/app/adjudication.json` — the exact output of `/app/adjudicate.py`
   run on `/app/policy.json` + `/app/claims.jsonl`.

## The adjudication pipeline (exact, in order)

All arithmetic is in **integer cents**. Step 3's floor is the only
non-integer handling in the whole pipeline — there is no rounding anywhere
else (in particular round-half-up is never applied to the final payable;
the final `payable_cents` is exactly the integer produced by steps 1–5).

1. **Eligibility.** A claim is eligible iff `category` is NOT in
   `excluded_categories` AND `policy_start <= date <= policy_end`
   (inclusive). Otherwise it is `denied`. Reason-code priority: an excluded
   category always wins over the window check, even if the date is also out
   of window — `"excluded_category"` beats `"out_of_window"`.
2. **Deductible (eligible claims only).** `covered = max(0, amount_cents -
   deductible_cents)`.
3. **Coinsurance.** `payable_pre_cap = floor(covered * (100 -
   coinsurance_percent) / 100)` — i.e. integer multiplication followed by
   **floor division** (`//` in Python; truncation toward zero).
4. **Per-claim cap.** `payable = min(payable_pre_cap, per_claim_cap_cents)`.
5. **Annual aggregate cap.** Only *eligible* claims consume the budget
   (denied claims never do). Take the eligible claims **sorted by `id`
   ascending using Python's normal string comparison, stable** (equal ids
   keep their original line order — duplicates are possible). Maintain a
   running `paid` total. Process in that order: if `paid + payable <=
   annual_aggregate_cap_cents`, the claim is paid in full. Otherwise the
   claim is **truncated**: it is paid only the remaining budget
   (`annual_aggregate_cap_cents - paid`, i.e. the partial remainder), the
   cap is now exhausted, and **every subsequently processed eligible claim**
   gets `payable_cents` 0.

## Decisions and reason codes (exact lists, order matters)

- Denied: `decision = "denied"`, `payable_cents = 0`, reason codes exactly
  `["excluded_category"]` or `["out_of_window"]`.
- Eligible (not cap-exhausted): `decision = "approved"`:
  - `"deductible_applied"` if `amount_cents > covered` (the deductible
    absorbed any part of the amount, even the whole amount);
  - `"coinsurance_applied"` if `covered > 0` and `coinsurance_percent > 0`;
  - `"per_claim_cap_applied"` if `payable_pre_cap > per_claim_cap_cents`;
  - `"aggregate_truncated"` if the aggregate cap truncated this claim to
    the remaining budget (appended after the per-claim-cap code);
  - if the list is still empty, exactly `["eligible"]` (e.g. a zero-amount
    claim). An approved claim may legally have `payable_cents = 0` (e.g.
    fully absorbed by the deductible).
- Eligible but cap-exhausted: `decision = "approved_zero"`,
  `payable_cents = 0`, reason codes exactly `["aggregate_exhausted"]`.

## Output schema (`<out.json>`)

```json
{
  "claims": [
    {"id": "...", "decision": "approved|approved_zero|denied",
     "payable_cents": 0, "reason_codes": ["..."]}
  ],
  "aggregate": {"paid_cents": 0, "cap_remaining_cents": 0}
}
```

- `claims` contains **every input claim** (denied and approved alike),
  sorted by `id` ascending with stable ordering for duplicate ids (same
  rule as step 5).
- `aggregate.paid_cents` = sum of every claim's `payable_cents`.
- `aggregate.cap_remaining_cents` = `annual_aggregate_cap_cents` minus
  `paid_cents` (never negative).
- An empty claims file yields `claims: []`, `paid_cents: 0`, and
  `cap_remaining_cents` equal to the full aggregate cap.

## How the grader probes it

- Re-runs `/app/adjudicate.py` on the visible fixtures and compares the
  output with its own independent recomputation of the pipeline above.
- Requires `/app/adjudication.json` to equal that same recomputation.
- Re-runs `/app/adjudicate.py` on hidden `(policy, claims)` bundles you
  have not seen — leap-day window boundaries (a policy whose window is the
  single day `2024-02-29`), aggregate exhaustion mid-sort with truncated
  partial payments, duplicate ids (stable tie ordering), zero-amount
  claims, exclusion precedence over the window check, and all-denied sets —
  and compares every decision, `payable_cents`, reason-code list (order
  included) and the aggregate totals against the recomputation. Any
  deviation — including a hardcoded visible answer — fails.

Do not modify the fixtures. Only `python3` from the standard library may be
used; no network access is available or needed.