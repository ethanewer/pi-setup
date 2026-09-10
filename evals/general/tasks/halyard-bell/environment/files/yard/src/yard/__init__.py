"""Halyard Yard — a container-freight yard orchestration service.

Halyard models a small railroad freight yard that receives containers through
gate lanes, moves them about with stacker cranes, holds temperature-sensitive
reefers in cold storage, and rolls them onto outbound trains at a rail depot.

Each sub-system exposes Prometheus-style metrics that the on-call tier turns
into alerting rules.  This package is the *source of truth* for what those
metrics mean and what the alerting contract is.  The operational meaning of
every metric, threshold and alert is documented in ``docs/runbook.md``; the
constants here and the runbook must never drift apart (a test enforces it).
"""

from .alerting import GATE_CEILING, CRANE_FAULT_LIMIT, REEFER_TOLERANCE, DISPATCH_SLA_SECONDS  # noqa: F401
from .simulator import YardSimulator  # noqa: F401

__version__ = "2.4.0"
