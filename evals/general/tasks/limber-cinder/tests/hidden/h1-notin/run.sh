#!/bin/bash
# Hidden case 1: default-undefined membership in its OTHER syntactic forms
# (not-in and inside if/else conditions) - inputs the upstream regression
# test does not use (it only covers plain `in` in an interpolation).
set -u
python3 - <<'PY'
from jinja2 import Environment
env = Environment()
assert env.from_string('{{ "foo" not in missing }}').render() == "True"
assert env.from_string('{% if "a" in missing %}yes{% else %}no{% endif %}').render() == "no"
assert env.from_string('{% if "a" not in missing %}yes{% else %}no{% endif %}').render() == "yes"
assert env.from_string('{{ "a" in missing and "b" in missing }}').render() == "False"
print("h1 ok")
PY