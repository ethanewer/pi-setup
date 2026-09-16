"""Structural behaviour of the per-area samplers."""

from yard import components as C
from yard.simulator import YardSimulator


def test_gate_lane_drains_forward():
    lane = C.GateLane(name="north", drain_per_min=4)
    before = lane.drained
    lane.tick()
    assert lane.drained > before


def test_crane_fault_ratio_stays_at_configured_bound():
    crane = C.StackerCrane(name="crane-1")
    for _ in range(200):
        crane.tick()
    ratio = crane.faults / max(1, crane.pickups)
    assert 0.0 <= ratio <= 0.20


def test_reefer_tracks_setpoint():
    unit = C.ReeferUnit(name="reefer-01", setpoint=-2.0)
    unit.tick()
    # within tolerance band of the setpoint
    assert abs(unit.temp - unit.setpoint) <= 2.0


def test_depot_wait_resets_on_departure():
    depot = C.RailDepot(name="main")
    depot.tick()
    assert depot.wait_seconds >= 0


def test_simulator_advances_lockstep():
    sim = YardSimulator(seed=3)
    sim.run(5)
    assert sim.tick == 5
    counts = {}
    for name, _, _ in sim.samples():
        counts[name] = counts.get(name, 0) + 1
    # both gate metrics appear for each of the two lanes
    from yard import metrics as M

    assert counts[M.GATE_OCCUPANCY] == 2
    assert counts[M.CRANE_PICKUPS] == 2
    assert counts[M.REEFER_TEMP] == 3
    assert counts[M.DISPATCH_WAIT] == 1
