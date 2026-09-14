#!/bin/bash
# Hidden case 3: membership with a non-string key, membership against the
# undefined value returned for a missing attribute of a real object, and
# membership with DebugUndefined - none of these inputs are used by the
# upstream regression test (which uses the string 'foo' against a bare
# undefined name with the default type).
set -u
python3 - <<'PY'
from jinja2 import DebugUndefined, Environment
env = Environment()
assert env.from_string('{{ 1 in missing }}').render() == "False"
assert env.from_string('{{ "foo" in foo.missing }}').render(foo=42) == "False"
assert env.from_string('{{ 42 not in missing }}').render() == "True"
env2 = Environment(undefined=DebugUndefined)
assert env2.from_string('{{ "foo" in missing }}').render() == "False"
assert env2.from_string('{{ "foo" not in missing }}').render() == "True"
print("h3 ok")
PY