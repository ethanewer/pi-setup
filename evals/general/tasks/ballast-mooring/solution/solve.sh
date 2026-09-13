#!/bin/bash
# Oracle for ballast-mooring: applies the one-line fix to DateFormatter's
# substring-parse trailing-token termination in the real netty tree at
# /app/src, writes /app/summary.md, then proves the fix with the project's own
# Maven tooling: the upstream regression test (extracted from the fix commit
# into /opt/golden at image build time) must pass offline, and the direct
# all-API reproduction must print the date. Reads only /app, /solution and
# /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied DateFormatter trailing-token fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: parsing an HTTP date from a slice of a longer header - the way a
Set-Cookie header's Expires value is read when other attributes follow it -
quietly returned `null` whenever the token that completes the parse happened
to be the last token of the slice. `DateFormatter.parse1(CharSequence, start,
end)` scans tokens between `start` and `end` and finalises each token with the
delimiter position; but the FINAL token (the one running up to `end`) was
finalised with `txt.length()` instead of `end`, so all bytes after `end` were
absorbed into it and it no longer looked like a date. The identical date text
parses fine on its own (and as the last attribute), so the loss was silent:
the cookie's expiration was dropped and it degraded to a session cookie.

Fix: finalise the trailing token with the parse range end (`end`) instead of
the sequence length. One-line change in the single source file where the
scanner lives; nothing else touched.

Verification with the project's own tooling: `mvn -o -pl codec-base test`
passes the upstream regression test for this bug (planted from /opt/golden)
14/14 offline, and the direct reproduction
`DateFormatter.parseHttpDate("Set-Cookie: foo=bar; Expires=Sun 08:49:37 06 Nov
1994; Path=/", start, end)` now prints `Sun Nov 06 08:49:37 UTC 1994` instead
of `null`.
MD

# Prove the fix with the project's own test runner: plant the upstream
# regression test (golden bytes from /opt/golden) and run it offline.
cp /opt/golden/DateFormatterTest.java codec-base/src/test/java/io/netty/handler/codec/DateFormatterTest.java
if ! mvn -o -pl codec-base test -Dtest=DateFormatterTest \
        -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true \
        > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -25 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "Tests run: 14, Failures: 0" /tmp/oracle_golden.log || {
    echo "oracle: surefire summary missing; tail:" >&2
    tail -15 /tmp/oracle_golden.log >&2
    exit 1
}

# Direct reproduction through the public API against the module's own
# compiled classes (deterministic under TZ=UTC, set by the image).
cp /solution/Repro.java /tmp/Repro.java
if ! javac -cp codec-base/target/classes:common/target/classes -d /tmp /tmp/Repro.java > /tmp/oracle_javac.log 2>&1; then
    echo "oracle: javac failed; tail:" >&2
    tail -15 /tmp/oracle_javac.log >&2
    exit 1
fi
OUT=$(java -cp /tmp:codec-base/target/classes:common/target/classes Repro)
RC=$?
[ "$RC" -eq 0 ] && [ "$OUT" = "parsed: Sun Nov 06 08:49:37 UTC 1994" ] || {
    echo "oracle: direct repro failed rc=$RC out='$OUT'" >&2
    exit 1
}
echo "oracle: direct repro OK: $OUT"

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- codec-base/src/test/java/io/netty/handler/codec/DateFormatterTest.java || {
    echo "oracle: could not restore DateFormatterTest.java" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression suite green, repro OK"
exit 0