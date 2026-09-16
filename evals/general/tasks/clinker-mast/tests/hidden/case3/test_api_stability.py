"""Hidden case 3 (part 1): the task must not change any existing public API
signature.  `api_snapshot.json` was captured from the pristine pinned
checkout (commit 26d48e0634e6ee9cdc0533996db289ce4b430177, httpx 0.28.1)
with the same interpreter the trial uses; the feature work must leave every
recorded signature byte-identical.
"""

import inspect
import json
from pathlib import Path

import httpx

SNAPSHOT = json.loads((Path(__file__).parent / "api_snapshot.json").read_text())


def test_metadata_still_matches_pinned_revision() -> None:
    assert SNAPSHOT["_meta"]["httpx_version"] == httpx.__version__
    assert SNAPSHOT["_meta"]["pinned_revision"] == "26d48e0634e6ee9cdc0533996db289ce4b430177"


def test_no_existing_public_signature_changed() -> None:
    mismatches = []
    for path, want in SNAPSHOT.items():
        if path == "_meta":
            continue
        obj = httpx
        for part in path.split(".")[1:]:
            obj = getattr(obj, part)
        got = str(inspect.signature(obj))
        if got != want:
            mismatches.append(f"{path}:\n  frozen: {want}\n  now:    {got}")
    assert not mismatches, "existing public API signatures changed:\n" + "\n".join(mismatches)


def test_meta_keys_are_reported() -> None:
    # Guard that the snapshot carries the expected metadata shape.
    assert set(SNAPSHOT["_meta"]) == {"pinned_revision", "httpx_version"}