import copy
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

from yaml.config_overlay import DELETE, apply_overlay, load_overlay


CLI = sys.argv[1]


def rejects(text):
    try:
        load_overlay(text)
    except (TypeError, ValueError, yaml.YAMLError):
        return
    raise AssertionError("accepted invalid overlay: %r" % text)


def rejects_at_load_or_apply(text, base):
    try:
        loaded = load_overlay(text)
    except (TypeError, ValueError, yaml.YAMLError):
        return
    try:
        apply_overlay(base, loaded)
    except (TypeError, ValueError):
        return
    raise AssertionError("accepted invalid structure: %r" % text)


def test_input_and_output_isolation():
    base = {"nested": {"items": [{"name": "base"}]}, "keep": [1, {"v": 2}]}
    overlay = {"nested": {"items": [{"name": "overlay"}]}, "new": [{"x": [3]}]}
    base_before = copy.deepcopy(base)
    overlay_before = copy.deepcopy(overlay)
    result = apply_overlay(base, overlay, list_mode="replace")
    result["nested"]["items"][0]["name"] = "changed"
    result["new"][0]["x"].append(4)
    result["keep"].append(5)
    assert base == base_before
    assert overlay == overlay_before


def test_delete_edges():
    rejects("!delete\n")
    rejects("x: !delete [one]\n")
    rejects("x: {nested: !delete [one]}\n")
    rejects("x: [!delete]\n")
    rejects_at_load_or_apply(
        "x: {nested: [!delete \"\"]}\n", {"x": {"nested": [1]}})
    for bad in (
        {"new": [DELETE]},
        {"new": {"nested": [DELETE]}},
        {DELETE: "bad"},
    ):
        try:
            apply_overlay({}, bad)
        except (TypeError, ValueError):
            pass
        else:
            raise AssertionError("malformed DELETE placement was accepted")
    assert apply_overlay({}, {"new": {"gone": DELETE, "kept": {"v": 1}}}) == {
        "new": {"kept": {"v": 1}}}
    assert apply_overlay({}, {"new": [{"gone": DELETE, "kept": 1}]}) == {
        "new": [{"kept": 1}]}
    try:
        apply_overlay({}, {"new": (DELETE,)})
    except ValueError:
        pass
    else:
        raise AssertionError("DELETE inside tuple was accepted")
    rejects_at_load_or_apply("root: &r {self: *r}\n", {})
    assert apply_overlay({"missing": 1}, load_overlay("missing: !delete\n")) == {}


def test_recursive_list_policies():
    base = {"a": {"items": [1, 2]}, "b": [{"items": ["x", "y"]}]}
    overlay = {"a": {"items": [2, 3]}, "b": [{"items": ["y", "z"]}]}
    assert apply_overlay(base, overlay, list_mode="replace") == {
        "a": {"items": [2, 3]}, "b": [{"items": ["y", "z"]}]}
    assert apply_overlay(base, overlay, list_mode="append") == {
        "a": {"items": [1, 2, 2, 3]},
        "b": [{"items": ["x", "y"]}, {"items": ["y", "z"]}]}
    assert apply_overlay(base, overlay, list_mode="unique") == {
        "a": {"items": [1, 2, 3]},
        "b": [{"items": ["x", "y"]}, {"items": ["y", "z"]}]}


def test_safe_yaml_and_existing_behavior():
    for text in (
        "x: !!python/object/apply:os.system ['echo bad']\n",
        "x: !!python/name:builtins.eval\n",
        "x: !not-registered value\n",
    ):
        rejects(text)
    assert yaml.safe_load("defaults: &d {enabled: true, count: 2}\nitem:\n  <<: *d\n") == {
        "defaults": {"enabled": True, "count": 2},
        "item": {"enabled": True, "count": 2},
    }
    dumped = yaml.safe_dump({"z": 1, "a": ["v"]}, sort_keys=False)
    assert yaml.safe_load(dumped) == {"z": 1, "a": ["v"]}
    assert yaml.safe_load("flag: yes\nnumber: 0x10\n") == {"flag": True, "number": 16}


def test_cli_invalid_inputs():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        base = root / "base.yml"
        overlay = root / "overlay.yml"
        output = root / "out.yml"
        base.write_text("x: 1\n", encoding="utf-8")
        invalid = [
            "- not-a-mapping\n",
            "x: !!python/object/apply:os.system ['echo bad']\n",
            "x: [2]\n",
        ]
        for text in invalid:
            overlay.write_text(text, encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, CLI, str(base), str(overlay), str(output)],
                env=dict(os.environ, PYTHONPATH="/app/pyyaml/lib"),
                capture_output=True,
                text=True,
            )
            assert proc.returncode != 0, (text, proc.stdout, proc.stderr)
            assert proc.stderr.strip(), "CLI gave no diagnostic"


test_input_and_output_isolation()
test_delete_edges()
test_recursive_list_policies()
test_safe_yaml_and_existing_behavior()
test_cli_invalid_inputs()
print("hidden cases: PASS")
