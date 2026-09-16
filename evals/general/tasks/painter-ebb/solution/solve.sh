#!/bin/bash
# Oracle for painter-ebb: writes the required reproduction, repairs the real
# defect in the mypy checkout at /app/src, and produces the diagnosis. It
# reads only the upstream tree and its own /solution payload (never /tests).
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# Sanity: this must be the real mypy tree at the buggy revision.
[ -f mypy/checkexpr.py ] || { echo "oracle: not a mypy tree" >&2; exit 1; }

# The agent-owned deliverable: a genuine failing reproduction of the bug.
cat > /app/repro.py <<'PY'
from typing import Optional, Type, TypeVar, Union


class A:
    def __init__(self, value: str = "") -> None:
        pass


class B:
    def __init__(self, value: str = "") -> None:
        pass


T = TypeVar("T", bound=Union[A, B])


def make(ftype: Type[T], value: Optional[str]) -> T:
    if value is None:
        return ftype()
    return ftype(value)


reveal_type(make(A, "a"))
reveal_type(make(B, None))
PY

# Apply the real fix (authored in /solution).
python3 /solution/fix_mypy_type_type_union.py || exit 1

cat > /app/diagnosis.md <<'MD'
## Diagnosis: Type[T] constructor calls with a union-bounded TypeVar

### Where
mypy/checkexpr.py -- ExpressionChecker.analyze_type_type_callee, the code
that turns a Type[item] expression used as a call target into a callable
callee, and specifically the branch for a TypeVarType item.

### Root cause
A parameter declared Type[T] with T bounded by a union of classes (say
Union[A, B]) is analysed by first building the constructor callable for the
upper bound, which is a UNION of the two constructors (one per class). The
code then substitutes the TypeVar instance T into each constructor's return
type, but the substitution only handled plain CallableType and Overloaded
callees; a UnionType callee fell through unchanged, so its items kept their
own return types (A and B). Every constructor call through the Type[T]
parameter was therefore checked as returning "A | B" instead of T, and the
return statement was rejected with "Incompatible return value type" even
though the checker had already revealed the precise constructed class.

### Fix
Factored the return-type substitution into a helper that recurses into the
union (over get_proper_type / relevant_items, the same traversal used to
build the callee union) and rewrites every branch's return type to the
TypeVar instance, so calls through a union-bounded Type[T] parameter type
check correctly in every branch, including nested unions.

### Verification
The reproduction (/app/repro.py) type-checks cleanly; the project's own
check-classes regression case for this behaviour and the testTypeUsingTypeC*
family of existing cases pass under pytest, as do the union-bound cases that
previously forced an updated expected reveal.
MD

# Oracle sanity check with the project's own CLI.
if python3 -m mypy --no-incremental --cache-dir=/tmp/oracle_cache /app/repro.py; then
    echo "oracle: mypy /app/repro.py clean (exit 0)"
else
    echo "oracle: WARNING mypy still reports on the repro" >&2
    exit 1
fi
exit 0