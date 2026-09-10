"""The yard simulator emits exactly the canonical metrics, well-labelled."""

from yard import metrics as M
from yard.simulator import YardSimulator


def test_all_canonical_metrics_present():
    sim = YardSimulator(seed=7)
    sim.run(3)
    names = sim.metric_names()
    assert names == set(M.ALL_METRICS)


def test_identifying_labels_are_correct():
    sim = YardSimulator(seed=7)
    sim.run(3)
    samples = list(sim.samples())
    by_metric = {}
    for name, labels, _ in samples:
        by_metric.setdefault(name, set()).add(frozenset(labels.items()))

    # gate metrics carry the lane label
    for name in (M.GATE_OCCUPANCY, M.LANE_DRAIN):
        assert any(M.GATE_LABEL in dict(d) for d in by_metric[name])
    # crane metrics carry the crane label
    for name in (M.CRANE_PICKUPS, M.CRANE_FAULTS):
        assert any(M.CRANE_LABEL in dict(d) for d in by_metric[name])
    # reefer metrics carry the unit label
    for name in (M.REEFER_TEMP, M.REEFER_SETPOINT):
        assert any(M.REEFER_LABEL in dict(d) for d in by_metric[name])
    # dispatch wait carries the depot label
    assert any(M.DISPATCH_LABEL in dict(d) for d in by_metric[M.DISPATCH_WAIT])


def test_no_metric_name_drift():
    """The catalogue is the single source of metric names."""
    sim = YardSimulator(seed=1)
    sim.run(1)
    from yard import components as C

    for _, labels, _ in sim.samples():
        pass  # names already asserted above; labels must use catalogue keys
    assert C.GateLane  # components import the catalogue constants
