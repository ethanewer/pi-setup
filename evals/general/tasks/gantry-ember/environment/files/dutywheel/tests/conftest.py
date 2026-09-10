"""Make the package importable when pytest runs from the project root."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest

_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="session")
def roster_path():
    """Path to the shipped sample crew roster."""
    return _ROOT / "samples" / "engineering.json"


@pytest.fixture(scope="session")
def roster(roster_path):
    """The shipped sample crew roster, loaded and validated."""
    from dutywheel.crew import load_roster
    return load_roster(roster_path)