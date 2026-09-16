#!/bin/bash
# Hidden case (quoin-swell): the dash path listed alongside other valid
# search paths. `fd . - docs` must search BOTH the literal "-" directory and
# the plain "docs" directory; a partial implementation that only handles the
# exact `fd . -` shape (or drops "-" silently as the parent does) fails.
# The upstream regression test passes a single dash path only.
set -u
FD_BIN=${FD_BIN:-/app/src/target/debug/fd}
work=$(mktemp -d /tmp/qsw-multipath.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/-" "$work/docs" || exit 1
echo x > "$work/-/one.txt" || exit 1
echo x > "$work/docs/two.txt" || exit 1
( cd "$work" && "$FD_BIN" . - docs ) > "$work/raw" 2>&1
rc=$?
[ "$rc" -eq 0 ] || exit 1
sort "$work/raw" > "$work/out"
printf '%s\n' "./-/one.txt" "docs/two.txt" | sort > "$work/want"
cmp -s "$work/want" "$work/out" || exit 1
exit 0