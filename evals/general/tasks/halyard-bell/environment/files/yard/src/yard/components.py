"""Per-sub-system samplers for the Halyard yard.

Each class models one physical area of the yard and advances one minute at a
time.  At every tick it publishes the metric samples for its area.  The
simulator in :mod:`yard.simulator` drives them all in lockstep.

The point of these classes is not to be a faithful queuing engine; it is to
give the four alertable failure modes a concrete, observable home so the
metrics name catalogue and the alerting contract have something real to attach
to.  Each sampler exposes a ``tick()`` that mutates a fresh time-step and a
``samples()`` sequence of ``(metric, labels_dict, value)`` tuples.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

from . import metrics as M


@dataclass
class GateLane:
    """A reception lane: trucks queue here until a crane drains them."""

    name: str
    capacity: float = 60.0
    drain_per_min: float = 3.0
    occupancy: int = 0
    drained: int = 0

    def tick(self) -> None:
        # Container handling floods the lane; the crane takes a set amount out.
        arrival = 2 if random.random() < 0.7 else 6
        self.occupancy += arrival
        self.occupancy = max(0, self.occupancy - round(self.drain_per_min))
        self.drained += round(self.drain_per_min)

    def samples(self):
        yield M.GATE_OCCUPANCY, {M.GATE_LABEL: self.name}, float(self.occupancy)
        yield M.LANE_DRAIN, {M.GATE_LABEL: self.name}, float(self.drained)


@dataclass
class StackerCrane:
    """A yard crane that moves containers between lanes and stacks."""

    name: str
    pickup_rate: float = 5.0
    fault_ratio: float = 0.02
    pickups: int = 0
    faults: int = 0

    def tick(self) -> None:
        attempts = max(1, round(self.pickup_rate))
        self.pickups += attempts
        if random.random() < self.fault_ratio:
            # each faulty grab is one failed attempt among the pickups
            self.faults += max(1, round(self.fault_ratio * attempts))

    def samples(self):
        yield M.CRANE_PICKUPS, {M.CRANE_LABEL: self.name}, float(self.pickups)
        yield M.CRANE_FAULTS, {M.CRANE_LABEL: self.name}, float(self.faults)


@dataclass
class ReeferUnit:
    """A temperature-controlled storage unit (a "reefer")."""

    name: str
    setpoint: float = 4.0
    temp: float = 4.0
    drift: float = 0.0

    def tick(self) -> None:
        self.temp = round(self.setpoint + self.drift + random.uniform(-0.2, 0.2), 2)

    def samples(self):
        yield M.REEFER_TEMP, {M.REEFER_LABEL: self.name}, float(self.temp)
        yield M.REEFER_SETPOINT, {M.REEFER_LABEL: self.name}, float(self.setpoint)


@dataclass
class RailDepot:
    """Outbound rail depot; containers wait here for the next train."""

    name: str
    wait_seconds: float = 300.0

    def tick(self) -> None:
        # Trains depart every 15 minutes; between departures the oldest wait
        # grows, then resets when a train rolls.
        self.wait_seconds += 60.0
        if int(self.wait_seconds // 900) % 15 == 0:  # a departure
            self.wait_seconds = max(0.0, self.wait_seconds - 2400.0)

    def samples(self):
        yield M.DISPATCH_WAIT, {M.DISPATCH_LABEL: self.name}, float(self.wait_seconds)
