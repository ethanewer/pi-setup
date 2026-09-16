#!/bin/bash
# Oracle for chainplate-brackish: applies the one-hunk fix to the real
# pylint tree at /app/src (the protected-access check must treat
# '<first method parameter>.__class__' as equivalent to type(self)), writes
# /app/summary.md, then proves the work with the project's own test harness:
# the CLI reproduction (only the other.__class__ line may still warn) plus
# the golden functional test baked at /opt/golden and the project's existing
# access/ functional tests, all offline. Reads only /app, /solution and
# /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

[ "$(git rev-parse HEAD)" = "9242406e364f537f91e99564400944f685f8b079" ] || {
    echo "oracle: HEAD is not the pinned parent commit" >&2; exit 1
}

git apply --check /solution/class_checker.patch || {
    echo "oracle: class_checker.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/class_checker.patch
echo "oracle: applied protected-access self.__class__ fix"

# Reproduction: only the other.__class__ line may warn.
cat > /tmp/oracle_repro.py <<'PY'
class Widget:
    _attr = None
    def access_via_self_class(self):
        if self.__class__._attr is None:
            return self.__class__._attr
        return None
    def access_via_other_object_class(self, other):
        return other.__class__._attr
PY
OUT=$(python3 -m pylint /tmp/oracle_repro.py --disable=all --enable=protected-access --score=n --msg-template='{line}:{msg_id}' 2>&1)
get_w0212_lines() {
    printf '%s\n' "$1" | sed -n 's/^\([0-9][0-9]*\):W0212$/\1/p' | sort -n | tr '\n' ' ' | sed 's/ $//'
}
GOT=$(get_w0212_lines "$OUT")
[ "$GOT" = "8" ] || {
    echo "oracle: repro W0212 lines '$GOT' != '11' after fix; full output:" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
}
echo "oracle: repro OK (W0212 only on the other.__class__ line 8)"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: pylint's `protected-access` check (W0212) emitted a spurious warning
when a protected class member was read through `self.__class__` inside an
instance method. `self.__class__` is exactly the class object of the
method's first parameter — the same value `type(self)` produces — and the
check already exempts the `type(self)` spelling. The result was that any
method reading a class attribute through `self.__class__` failed a clean
lint run while the identical access written as `type(self)` passed.

Fix: in the protected-access visitor, an attribute access whose expression
is `<first method parameter>.__class__` is now treated as equivalent to
`type(self)` and returns early, exactly like the existing
`_is_type_self_call` exemption. A small helper recognises an Attribute node
with attrname `__class__` whose value is the method's mandatory first
parameter (however it is named), mirroring the semantics used by
`_is_mandatory_method_param`. Accesses through *another* object's class
(e.g. `other.__class__._attr`) are untouched and keep warning.

Verification: the CLI reproduction now reports W0212 only on the
`other.__class__` line (the `self.__class__` reads are silent); the golden
functional test for this bug (planted from /opt/golden) passes under the
project's own pytest harness together with the project's existing
`access/` functional tests.
MD

# Plant the golden functional test (upstream regression test for this bug,
# extracted from the fix commit at image build time; never part of this task
# tree), run the project's own pytest harness on it plus the existing
# access/ functional family, then restore the two files so the tree is
# byte-clean except for the fixed source file.
cp /opt/golden/access_to_protected_members.py tests/functional/a/access/access_to_protected_members.py
cp /opt/golden/access_to_protected_members.txt tests/functional/a/access/access_to_protected_members.txt
if ! python3 -m pytest tests/test_functional.py \
        -k "access_to_protected_members or access_member_before_definition or access_to__name__ or access_attr_before_def_false_positive" \
        -q -p no:cacheprovider > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: pytest run failed; tail:" >&2
    tail -30 /tmp/oracle_pytest.log >&2
    git restore --worktree --source=HEAD -- \
        tests/functional/a/access/access_to_protected_members.py \
        tests/functional/a/access/access_to_protected_members.txt
    exit 1
fi
grep -E "passed|failed" /tmp/oracle_pytest.log | tail -2
[ "$(grep -cE 'failed' /tmp/oracle_pytest.log)" = "0" ] || {
    echo "oracle: pytest reported failures" >&2
    git restore --worktree --source=HEAD -- \
        tests/functional/a/access/access_to_protected_members.py \
        tests/functional/a/access/access_to_protected_members.txt
    exit 1
}
git restore --worktree --source=HEAD -- \
    tests/functional/a/access/access_to_protected_members.py \
    tests/functional/a/access/access_to_protected_members.txt
rm -f /tmp/oracle_repro.py /tmp/oracle_pytest.log

echo "oracle: fix applied, summary written, golden + access/ suite green, repro OK"
exit 0