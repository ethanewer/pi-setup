"""Lockstep simulator that ties the yard sub-systems together."""

from __future__ import annotations

from . import metrics as M
from .alerting import ALERT_NAMES
from .components import GateLane, RailDepot, ReeferUnit, StackerCrane


class YardSimulator:
    """Advances every yard area one minute at a time and yields its samples.

    A fresh simulator has a canonical, deterministic default topology so that
    tests and demos share one picture of the yard: two gate lanes, a pair of
    cranes, three reefers and a single rail depot.
    """

    def __init__(self, seed: int = 0) -> None:
        self._rng = __import__("random").Random(seed)
        self.gates = [GateLane(name="north"), GateLane(name="south")]
        self.cranes = [
            StackerCrane(name="crane-1"),
            StackerCrane(name="crane-2"),
        ]
        self.reefers = [
            ReeferUnit(name="reefer-01", setpoint=4.0),
            ReeferUnit(name="reefer-02", setpoint=-2.0),
            ReeferUnit(name="reefer-03", setpoint=8.0),
        ]
        self.depot = RailDepot(name="main")
        self.tick = 0

    def step(self) -> None:
        """Advance the yard by one simulated minute."""
        self.tick += 1
        for area in (*self.gates, *self.cranes, *self.reefers, self.depot):
            area.tick()

    def run(self, minutes: int) -> None:
        for _ in range(minutes):
            self.step()

    def samples(self):
        """Yield every current sample as ``(metric, labels, value)``."""
        for area in (*self.gates, *self.cranes, *self.reefers, self.depot):
            yield from area.samples()

    def metric_names(self):
        return {s[0] for s in self.samples()}

    def label_keys(self):
        keys = set()
        for name, labels, _ in self.samples():
            keys.update(labels)
        return keys
