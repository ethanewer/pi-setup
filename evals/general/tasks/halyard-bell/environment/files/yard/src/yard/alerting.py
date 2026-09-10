"""The Halyard alerting contract.

This module is the single reference for the operational values the on-call
tier cares about.  ``docs/runbook.md`` describes the *reasoning* behind every
number; this module pins the numbers in code.  A pytest suite verifies the
runbook and this module agree, because a staged alerting rule that drifts from
these constants is exactly the kind of over-broad or over-narrow rule that
wakes somebody at 3am for nothing.

The four alerts and their fixed names are:

===============  ===================================================  ========
Alert name       What trip-wires it                                    Group
===============  ===================================================  ========
GateBacklogFault a gate lane over ceiling *and* not draining           gates
StackerFaultStorm a crane whose rolling fault ratio breaches the limit  cranes
ReeferColdChain  a reefer outside its own setpoint tolerance           reefers
DispatchAgeSLA   an outbound order past its dispatch SLA               depot
===============  ===================================================  ========

Every alert carries ``severity = "page"`` and inherits the identifying label
of the series that triggered it (one of ``lane`` / ``crane`` / ``unit`` /
``depot``).
"""

from __future__ import annotations

# --- Gate reception -------------------------------------------------------
# A lane is "over ceiling" when its occupancy exceeds this many trucks, and is
# "not draining" when fewer than this many containers are cleared per minute.
# A backlog is only a fault when BOTH hold; a busy-but-draining lane is fine.
GATE_CEILING = 60
GATE_DRAIN_FLOOR_PER_MIN = 2.0
# The backlog must persist across this long before it pages (the yard may
# clear a transient build-up on its own).
GATE_SUSTAIN_MIN = 10

# --- Stacker cranes -------------------------------------------------------
# Grab quality limit: a crane's fault ratio = faults / (pickups + faults).
# Above this ratio over the measurement window the crane is degrading.
CRANE_FAULT_LIMIT = 0.20
CRANE_WINDOW_MIN = 5

# --- Reefers --------------------------------------------------------------
# A unit is out of tolerance when |measured - setpoint| exceeds this (Celsius).
# It is a *breach* only after persisting beyond the icing/loading window.
REEFER_TOLERANCE = 2.0
REEFER_SUSTAIN_MIN = 5

# --- Rail depot -----------------------------------------------------------
# SLA: an outbound container must roll within this many seconds.  A wait above
# the SLA is actionable only once it has persisted across a full departure
# cadence (trains leave every DEPARTURE_CADENCE_MIN).
DISPATCH_SLA_SECONDS = 14400
DISPATCH_CADENCE_MIN = 15

ALERT_NAMES = (
    "GateBacklogFault",
    "StackerFaultStorm",
    "ReeferColdChain",
    "DispatchAgeSLA",
)
