# Halyard Yard — Operations Runbook

This runbook is the authoritative description of the Halyard yard's metrics
and its alerting contract. When you write or change alerting rules for Halyard,
this document — and the constants in `src/yard/alerting.py`, which must agree
with it — is what you implement.

Halyard has **four** sub-systems, each with exactly one alertable failure
mode. Every sub-system also has a **healthy-but-busy** state: the yard working
hard and fast without actually failing. An alerting rule that cannot tell the
two apart is *over-broad* and wakes people for nothing. The on-call tier will
not accept it.

## Metric catalogue

| Metric | Type | Identifying label | Meaning |
|---|---|---|---|
| `yard_gate_occupancy` | gauge | `lane` | trucks queued at a gate lane |
| `yard_lane_drain_total` | counter | `lane` | cumulative containers cleared from that lane |
| `yard_crane_pickups_total` | counter | `crane` | successful grabs by a crane |
| `yard_crane_faults_total` | counter | `crane` | failed grabs by a crane |
| `reefer_temp_celsius` | gauge | `unit` | measured temperature of a reefer unit |
| `reefer_setpoint_celsius` | gauge | `unit` | the unit's own frozen setpoint |
| `yard_dispatch_wait_seconds` | gauge | `depot` | age of the oldest container awaiting an outbound train |

All same-metric samples share the identifying label for that metric, so a rule
can key on `lane`, `crane`, `unit` or `depot` as appropriate. **Do not invent
metric names or labels**; Halyard only emits the seven metrics above.

## 1. Gate reception — `GateBacklogFault`

Containers arrive through gate lanes; stacker cranes clear each lane.

- A lane is **over ceiling** when `yard_gate_occupancy` exceeds **60** trucks.
- A lane is **not draining** when fewer than **2** containers per minute are
  cleared from it (`yard_lane_drain_total` rising slower than that).
- A lane is a **fault** only when it is over ceiling **and** not draining,
  sustained for **10 minutes**.

A busy gate lane with occupancy above 60 that is *still draining* at or above
the 2/minute floor is healthy-but-busy — the yard is simply handling a lot of
traffic. It must **not** alert. Alerting on occupancy alone, or on drain rate
alone, is over-broad.

> Required alert name: **`GateBacklogFault`**.

## 2. Stacker cranes — `StackerFaultStorm`

Cranes grab containers; sometimes a grab fails.

- Grab quality on a crane is its **fault ratio** =
  `rate(yard_crane_faults_total)` divided by
  `rate(yard_crane_pickups_total) + rate(yard_crane_faults_total)`, measured
  over a **5-minute** window.
- A crane is in a fault storm when its fault ratio exceeds **0.20** (20%) for a
  sustained window.
- Crane throughput varies with load: `rate()` returns a *per-second* rate.

A busy crane makes many pickups, so a handful of faults among them is normal.
Raw fault count, or a fault ratio using the wrong window, is over-broad (it
fires on throughput alone) or under-sensitive.

> Required alert name: **`StackerFaultStorm`**.

## 3. Reefer cold storage — `ReeferColdChain`

Reefers hold cargo at a unit-specific setpoint.

- A unit is **out of tolerance** when the absolute difference between
  `reefer_temp_celsius` and that unit's own `reefer_setpoint_celsius` exceeds
  **2.0 °C**.
- It is a **breach** only once it persists beyond the **5-minute** icing /
  loading window.

Setpoints differ per unit (a frozen unit sits at −2 °C while an ambient "dry"
unit sits at +8 °C). Comparing against an absolute temperature, or against the
wrong setpoint, is over-broad. A brief door-open dip that recovers within the
5-minute window must **not** alert.

> Required alert name: **`ReeferColdChain`**.

## 4. Rail dispatch — `DispatchAgeSLA`

Outbound containers roll onto trains at the depot.

- The dispatch SLA is **4 hours (14,400 seconds)** of wait
  (`yard_dispatch_wait_seconds`).
- Trains depart every **15 minutes**. A wait above the SLA is actionable only
  once it persists across a full departure cadence — i.e. sustained for
  **15 minutes**.
- A brief spike above the SLA that clears on the next departure (within the
  15-minute cadence) is normal queue turnover and must **not** alert.

> Required alert name: **`DispatchAgeSLA`**.

## Alert naming and labels

There are exactly four alerts, with exactly these names:

1. `GateBacklogFault`
2. `StackerFaultStorm`
3. `ReeferColdChain`
4. `DispatchAgeSLA`

Every rule must set the label **`severity: "page"`**. Each alert inherits the
identifying label of the series that triggered it (`lane`, `crane`, `unit` or
`depot`) from the source metric — do **not** hand-add or hand-remove those.
Do **not** add any other labels.

## Verification

Alerting rules are validated with Prometheus's own tooling:

- `promtool check rules <rules-file>` — syntactic validity.
- `promtool test rules <scenario-file>` — unit-tests which alerts fire at which
  evaluation times on a given input series, so the fire-on-right / don't-fire-on-
  the-wrong condition is proven, not assumed.

A rules file is only correct when it passes **both** on every scenario,
including the healthy-but-busy ones.
