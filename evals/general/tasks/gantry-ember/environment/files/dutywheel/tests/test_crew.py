"""Crew roster loading and validation tests."""
import pytest


def test_roster_loads_fifteen_members(roster):
    assert len(roster["members"]) == 15


def test_member_ids_are_unique(roster):
    ids = [m["id"] for m in roster["members"]]
    assert len(ids) == len(set(ids))


def test_every_member_has_required_fields(roster):
    for member in roster["members"]:
        assert set(member) == {"id", "name", "role", "windows"}
        assert isinstance(member["windows"], list)


def test_member_roles_are_valid(roster):
    from dutywheel.crew import VALID_ROLES
    assert {m["role"] for m in roster["members"]} <= VALID_ROLES


def test_roster_rejects_duplicate_ids(tmp_path):
    from dutywheel.crew import load_roster
    dup = tmp_path / "dup.json"
    dup.write_text(
        '{"members": ['
        '{"id": "x", "name": "X", "role": "primary", "windows": []},'
        '{"id": "x", "name": "Y", "role": "primary", "windows": []}]}'
    )
    with pytest.raises(ValueError):
        load_roster(str(dup))


def test_roster_rejects_unknown_role(tmp_path):
    from dutywheel.crew import load_roster
    bad = tmp_path / "bad.json"
    bad.write_text(
        '{"members": [{"id": "x", "name": "X", "role": "captain", '
        '"windows": []}]}'
    )
    with pytest.raises(ValueError):
        load_roster(str(bad))