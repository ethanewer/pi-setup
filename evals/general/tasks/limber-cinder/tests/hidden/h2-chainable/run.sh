#!/bin/bash
# Hidden case 2: membership against an undefined value reached through a
# ChainableUndefined chain (missing.bar), which the upstream regression
# test does not exercise (it only probes a bare undefined name).
set -u
python3 - <<'PY'
from jinja2 import ChainableUndefined, Environment
env = Environment(undefined=ChainableUndefined)
assert env.from_string('{{ "foo" in missing.bar }}').render() == "False"
assert env.from_string('{{ "foo" not in missing.bar }}').render() == "True"
assert env.from_string('{{ missing.bar["baz"] }}').render() == ""
assert env.from_string('{{ "x" in missing.a.b }}').render() == "False"
print("h2 ok")
PY