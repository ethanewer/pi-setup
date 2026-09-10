"""The alerting contract constants match the operational runbook.

These tests pin the numbers that live in ``src/yard/alerting.py`` to the values
the runbook documents, so the code and the runbook cannot drift.  If you ever
change an operational number, change it in BOTH places (this suite enforces it)
and in the alerting rules that realise it.
"""

from yard import alerting as A


def test_gate_contract():
    assert A.GATE_CEILING == 60
    assert A.GATE_DRAIN_FLOOR_PER_MIN == 2.0
    assert A.GATE_SUSTAIN_MIN == 10


def test_crane_contract():
    assert A.CRANE_FAULT_LIMIT == 0.20
    assert A.CRANE_WINDOW_MIN == 5


def test_reefer_contract():
    assert A.REEFER_TOLERANCE == 2.0
    assert A.REEFER_SUSTAIN_MIN == 5


def test_dispatch_contract():
    assert A.DISPATCH_SLA_SECONDS == 14400
    assert A.DISPATCH_CADENCE_MIN == 15


def test_alert_names_are_exactly_the_four():
    assert A.ALERT_NAMES == (
        "GateBacklogFault",
        "StackerFaultStorm",
        "ReeferColdChain",
        "DispatchAgeSLA",
    )


def test_alert_names_are_unique():
    assert len(set(A.ALERT_NAMES)) == len(A.ALERT_NAMES)
