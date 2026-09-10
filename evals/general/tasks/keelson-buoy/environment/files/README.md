# CargoOps — incident notes (2025-01-10)

## What happened

At **03:17 UTC on 2025-01-10** the nightly inventory-sync automation (job
`sync_inventory_20250110_0317`) wrote garbage over part of the `positions`
table in the `cargoops` database. The bad job has been quarantined; nothing
has touched the database since.

## Where the good data is

- The last intact snapshot of `positions` was taken by the nightly dump job on
  **2024-11-30 00:00 UTC** and is stored at
  `/app/backups/cargoops_base_20241130.sql`. It is a plain-SQL dump of the
  table as it stood at the snapshot moment — **before** the incident and
  **before** several legitimate cargo changes that happened after the
  snapshot.
- The `cargoops` database itself still carries the full operational ledger:
  every load/discharge change to a position that has happened **since the
  snapshot** is recorded in the database's change journal, with its timestamp
  and signed delta (positive = loaded, negative = discharged). No ledger
  history has been lost, truncated, or reset.

Nothing has been deleted from the database by the incident or by us. The only
damage is the overwritten figures; the surrounding record — which position is
which, its vessel, its tariff class, its seal tag, its timestamps — is intact.

## What `positions` means

`positions` is the live inventory table: one row per cargo lot, keyed by
`position_id`. The five columns other than the overwritten one are all
trustworthy as-is. The journal table in the same database records change
events for lots carried in `positions`.

## What is needed

Repair the overwritten figures so operations can resume, without losing or
reverting anything else. An analyst should be able to re-derive every
repaired figure from records that already exist in this container.