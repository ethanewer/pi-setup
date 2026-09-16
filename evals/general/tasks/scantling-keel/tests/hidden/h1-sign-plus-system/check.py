"""Hidden case h1: nonlinsolve([sign(x) + 1, x + y], [x, y]).
Fixed behaviour: NotImplementedError whose message names the solution type
(an interval). Anything else - especially a raw TypeError/AttributeError -
is a failure.
"""
import os
import sys

src = os.environ.get('SYMPY_SRC')
if src:
    sys.path.insert(1, os.path.abspath(src))

from sympy import nonlinsolve, sign, symbols  # noqa: E402

x, y = symbols('x y')
try:
    result = nonlinsolve([sign(x) + 1, x + y], [x, y])
except NotImplementedError as exc:
    msg = str(exc)
    if 'Interval' not in msg:
        print('h1 FAIL: NotImplementedError raised, but it does not name the '
              'solution type: %r' % msg.splitlines()[0])
        sys.exit(1)
    missing = [tok for tok in ['symbol x', 'Interval.open(-oo, 0)'] if tok not in msg]
    if missing:
        print('h1 FAIL: NotImplementedError message lacks per-input detail(s) %r: %r'
              % (missing, msg.splitlines()[0]))
        sys.exit(1)
    print('h1 PASS: NotImplementedError naming the solution type: %s'
          % msg.splitlines()[0])
    sys.exit(0)
except Exception as exc:  # noqa: BLE001 - report and fail
    print('h1 FAIL: LOW-LEVEL CRASH %s: %s' % (type(exc).__name__, str(exc)[:120]))
    sys.exit(1)
print('h1 FAIL: no exception raised; got %s: %r' % (type(result).__name__, result))
sys.exit(1)