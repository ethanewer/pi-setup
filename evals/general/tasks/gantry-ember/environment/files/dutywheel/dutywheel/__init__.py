"""dutywheel — on-call rotation for service crews.

The wheel assigns each duty cycle to one member of a crew.  The rotation
contract, enforced by the test suite:

* every cycle is carried by a member of the crew;
* the member who carried the previous cycle is never handed the next one
  while any other member is available;
* every process and every retry picks the same assignment for the same
  roster snapshot (the selection is fully reproducible).
"""
from dutywheel.crew import load_roster
from dutywheel.rotation import pick

__version__ = "0.6.0"
__all__ = ["load_roster", "pick", "__version__"]