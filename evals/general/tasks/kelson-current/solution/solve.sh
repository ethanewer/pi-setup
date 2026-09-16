#!/bin/bash
# Oracle for kelson-current: applies the real upstream fix for the gzip
# FEXTRA header-field bug to the netty/netty tree at /app/src (the gzip
# decoder must assemble the little-endian XLEN with an assignment - OR-ing
# into the -1 "no extra field" sentinel leaves it -1 so the extra field is
# never skipped - and must reset xlen to -1 at the start of each gzip
# member), writes the deliverable reproduction /app/repro.sh and
# /app/summary.md, creates the reproduction test class in the module's test
# package, and proves everything with Maven, fully offline.
# Reads only /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export MAVEN_OPTS="-Xmx4g -Dmaven.wagon.http.pool=false"

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch || { echo "oracle: git apply failed" >&2; exit 1; }
echo "oracle: applied the gzip FEXTRA header-field fix"

cp /solution/ReproTest.java \
   codec-compression/src/test/java/io/netty/handler/codec/compression/ReproTest.java \
   || { echo "oracle: cannot install reproduction test" >&2; exit 1; }
cp /solution/repro.sh /app/repro.sh || { echo "oracle: cannot write /app/repro.sh" >&2; exit 1; }
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh and the reproduction test class"

cat > /app/summary.md <<'MD'
# Change summary (oracle, kelson-current)

Bug: gzip byte streams whose header carries an extra field (the FEXTRA
flag, RFC 1952 - set by BGZF and other tools that store metadata in the
gzip header) cannot be decompressed by the gzip codec. Decoding throws a
DecompressionException ("decompression failure") and emits nothing, while
the identical bytes decode cleanly with the JDK's own GZIPInputStream.
Concatenated gzip members are also affected once a member with an extra
field appears: the second member fails to decode even when it is a plain
stream.

Cause: the gzip header parser keeps the extra-field length in a field that
doubles as the "no extra field" sentinel, initialised to -1. When FLG.FEXTRA
is set it OR-ed the two XLEN bytes into that field; OR-ing anything into -1
leaves it -1, so the extra field was never skipped and its bytes were handed
to the inflater as if they were compressed data. The two-byte XLEN was also
assembled in the wrong byte order (RFC 1952 specifies little-endian), and
the length state was not reset between concatenated gzip members, so a
first member's extra field leaked into the next member's header parsing.

Fix: assemble the little-endian XLEN with an assignment
(xlen = xlen2 << 8 | xlen1;) and reset xlen to -1 whenever a new gzip
member starts. Ordinary gzip output never sets FLG.FEXTRA, which is why the
bug only shows up for unusual-but-valid producers.

Verification: /app/repro.sh fails (DecompressionException, nonzero exit)
against the pristine pre-fix decoder file and passes against this tree; the
upstream regression test for this bug (planted from /opt/golden) passes
alongside the module's pre-existing JdkZlibTest suite; authored hidden cases
with a 300-byte extra field, a 512-byte extra field with a zero low XLEN
byte, and concatenated members mixing FEXTRA+FNAME with a plain member all
decode byte-for-byte.
MD
echo "oracle: wrote /app/summary.md"

echo "oracle: prove - golden test + current module suite on the fixed tree"
cp /opt/golden/JdkZlibTest.java \
   codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibTest.java
if ! mvn -o -pl codec-compression test \
        -Dtest=JdkZlibTest \
        -Dsurefire.failIfNoSpecifiedTests=true \
        -Dcheckstyle.skip=true -Dxml.format.skip=true -Dlicense.skip=true \
        > /tmp/oracle_golden.log 2>&1; then
    tail -25 /tmp/oracle_golden.log >&2
    echo "oracle: golden test did not pass; see /tmp/oracle_golden.log" >&2
    exit 1
fi
grep -qE 'Tests run: 24[,] Failures: 0[,] Errors: 0[,] Skipped: 0' /tmp/oracle_golden.log || {
    echo "oracle: golden run did not execute all 24 tests cleanly; see /tmp/oracle_golden.log" >&2
    exit 1
}
git restore --worktree --source=HEAD -- \
    codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibTest.java

echo "oracle: prove - reproduction both directions"
if ! /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; tail:" >&2
    tail -15 /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
cp codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java /tmp/oracle_decoder.java
cp /opt/prefix/JdkZlibDecoder.java \
   codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java
find codec-compression/target -name 'JdkZlibDecoder*.class' -delete 2>/dev/null || true
touch codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java
if /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix decoder (expected failure)" >&2
    exit 1
fi
cp /tmp/oracle_decoder.java \
   codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java
echo "oracle: repro fails on the pre-fix decoder, passes on the fixed tree"

echo "oracle: fix applied, deliverables written, module suite green, repro OK"
exit 0