#!/bin/bash
# Hidden case 4: the fix must NOT have over-broadened - membership against
# a strict-undefined value must still raise UndefinedError for both `in`
# and `not in`, and other strict failures must keep raising too.
set -u
python3 - <<'PY'
from jinja2 import Environment, StrictUndefined
from jinja2.exceptions import UndefinedError
env = Environment(undefined=StrictUndefined)
for tpl in ('{{ "foo" in missing }}', '{{ "foo" not in missing }}'):
    try:
        env.from_string(tpl).render()
    except UndefinedError:
        continue
    raise SystemExit("strict-undefined membership did not raise for %s" % tpl)
try:
    env.from_string('{{ missing.x }}').render()
except UndefinedError:
    pass
else:
    raise SystemExit("strict-undefined attribute access did not raise")
try:
    env.from_string('{{ missing|list }}').render()
except UndefinedError:
    pass
else:
    raise SystemExit("strict-undefined list() did not raise")
print("h4 ok")
PY