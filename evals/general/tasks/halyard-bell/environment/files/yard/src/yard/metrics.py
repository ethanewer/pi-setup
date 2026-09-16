"""Metric catalogue for the Halyard yard.

Exports the canonical metric names and their identifying label keys.  Every
sampler in :mod:`yard.components` publishes only these metric/label names, so
the whole alerting layer can be written against this catalogue rather than
against drifting string literals.

The values an operator is allowed to care about — thresholds, quality limits,
service windows — live in :mod:`yard.alerting`, not here.  This module only
claims *which* time series exist and *how they are labelled*.
"""

from __future__ import annotations

# --- Gate reception (inbound) ---------------------------------------------
# yard_gate_occupancy{lane}      trucks currently queued at a gate lane
# yard_lane_drain_total{lane}    cumulative containers cleared from that lane
GATE_OCCUPANCY = "yard_gate_occupancy"
LANE_DRAIN = "yard_lane_drain_total"
GATE_LABEL = "lane"

# --- Stacker cranes (yard movement) --------------------------------------
# yard_crane_pickups_total{crane}    successful grabs by a crane
# yard_crane_faults_total{crane}     failed grabs by a crane (dropped/erred)
CRANE_PICKUPS = "yard_crane_pickups_total"
CRANE_FAULTS = "yard_crane_faults_total"
CRANE_LABEL = "crane"

# --- Reefers (cold storage) ----------------------------------------------
# reefer_temp_celsius{unit}        measured temperature of a reefer unit
# reefer_setpoint_celsius{unit}    the unit's frozen setpoint (differs per unit)
REEFER_TEMP = "reefer_temp_celsius"
REEFER_SETPOINT = "reefer_setpoint_celsius"
REEFER_LABEL = "unit"

# --- Rail depot (outbound dispatch) --------------------------------------
# yard_dispatch_wait_seconds{depot}   age of the oldest container awaiting a
#                                     train at that depot
DISPATCH_WAIT = "yard_dispatch_wait_seconds"
DISPATCH_LABEL = "depot"

ALL_METRICS = (
    GATE_OCCUPANCY,
    LANE_DRAIN,
    CRANE_PICKUPS,
    CRANE_FAULTS,
    REEFER_TEMP,
    REEFER_SETPOINT,
    DISPATCH_WAIT,
)
