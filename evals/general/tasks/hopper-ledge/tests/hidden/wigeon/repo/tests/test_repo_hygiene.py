"""Repo hygiene: the checkout must stay free of generated output."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATED = set(['.cache_deps', '.deps', '.vendor', 'artifacts', 'build', 'dist', 'out', 'release'])


def test_no_generated_output_at_checkout_root():
    present = {p.name for p in ROOT.iterdir() if p.is_dir()}
    leaked = sorted(GENERATED & present)
    assert not leaked, (
        "generated build/dependency output left in the checkout: %s"
        % leaked
    )


def test_expected_top_level_layout():
    assert (ROOT / "wigeon").is_dir()
    assert (ROOT / "ci").is_dir()
    assert (ROOT / "tests").is_dir()
    assert not (ROOT / "out").exists()
    assert not (ROOT / ".deps").exists()
