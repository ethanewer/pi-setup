#!/bin/sh
set -u
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT HUP INT TERM
printf '0\n' > /logs/verifier/reward.txt
status=0
PYTHONPATH=/app/pyyaml/lib python3 - /app/pyyaml/lib/yaml/config_overlay.py /app/reproduce_overlay.py <<'PY'
import copy
import os
import subprocess
import sys
import tempfile
from pathlib import Path

module_path, cli_path = sys.argv[1:]
assert os.path.isfile(module_path)
assert os.path.isfile(cli_path)
import yaml
from yaml.config_overlay import DELETE, apply_overlay, load_overlay

base = {"service": {"port": 80, "tags": ["a", "b"], "old": True}, "keep": {"x": 1}}
original = copy.deepcopy(base)
overlay = load_overlay("service:\n  port: 8080\n  old: !delete\n  tags: [b, c]\nnew: yes\n")
assert overlay["service"]["old"] is DELETE
assert apply_overlay(base, overlay) == {"service": {"port": 8080, "tags": ["b", "c"]}, "keep": {"x": 1}, "new": True}
assert base == original

assert apply_overlay({"x": [1, {"a": 2}]}, {"x": [2, {"a": 3}]}, list_mode="append") == {"x": [1, {"a": 2}, 2, {"a": 3}]}
assert apply_overlay({"x": [1, 2]}, {"x": [2, 3, 3]}, list_mode="unique") == {"x": [1, 2, 3]}
for bad in ("bad", None, 3):
    try:
        load_overlay(bad)
    except (TypeError, AttributeError, ValueError, yaml.YAMLError):
        pass
    else:
        raise AssertionError("bad stream accepted")
for text in ("- one\n", "x: !python/object:builtins.eval nope\n", "x: !delete [a]\n"):
    try:
        load_overlay(text)
    except (ValueError, yaml.YAMLError):
        pass
    else:
        raise AssertionError("unsafe or malformed overlay accepted")
for args in (([], {"x": 1}), ({"x": 1}, []), ({"x": [1]}, {"x": [2]}, "bad")):
    try:
        if len(args) == 2:
            apply_overlay(*args)
        else:
            apply_overlay(args[0], args[1], list_mode=args[2])
    except (TypeError, ValueError):
        pass
    else:
        raise AssertionError("invalid merge accepted")

with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / "base.yml").write_text("a: 1\nitems: [x]\n", encoding="utf-8")
    (d / "overlay.yml").write_text("b: 2\nitems: [y]\n", encoding="utf-8")
    proc = subprocess.run([sys.executable, cli_path, str(d / "base.yml"), str(d / "overlay.yml"), str(d / "out.yml"), "--list-mode", "append"], env=dict(os.environ, PYTHONPATH="/app/pyyaml/lib"), capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    assert yaml.safe_load((d / "out.yml").read_text()) == {"a": 1, "items": ["x", "y"], "b": 2}
PY
visible_status=$?
if [ "$visible_status" -ne 0 ]; then
  status=$visible_status
fi
PYTHONPATH=/app/pyyaml/lib python3 /tests/hidden/hidden_test.py /app/reproduce_overlay.py
hidden_status=$?
if [ "$hidden_status" -ne 0 ]; then
  status=$hidden_status
fi
if [ "$status" -eq 0 ]; then
  reward=1
fi
exit "$status"
