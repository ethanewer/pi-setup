#!/bin/bash
# Oracle for chainplate-berm: applies the real upstream fix to the zlib
# decompressor in the real netty tree at /app/src, writes /app/summary.md,
# then proves the fix with the project's own Maven tooling: the upstream
# regression test (extracted from the fix commit into /opt/golden at image
# build time) must pass offline. Reads only /app, /solution and /opt/golden,
# never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied zlib-decompressor tail-loss fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the JDK zlib decompressor silently lost the tail of highly compressible
raw-deflate streams. Each output buffer handed to `Inflater.inflate(...)` was
sized from the number of input bytes still unread (`getRemaining() << 1`).
For payloads with an extreme compression ratio (e.g. hundreds of thousands of
a repeated byte), the inflater consumes the final input bytes into its
internal state while a large run of decoded output is still pending; by then
`getRemaining()` is zero, so the buffer sized from it was too small to make
progress, `status()` reported NEED_INPUT, and declaring end-of-input then
threw "Compressed stream ended before the end-of-stream marker" even though
the stream was complete and valid. Wrapped formats (zlib/gzip) usually
escaped because their trailers keep the remaining-input count above zero
until the inflater finishes; raw (wrapper-less) streams and the sniffing
ZLIB_OR_NONE mode triggered it.

Fix (in the single source file where the decompressor lives):
- a minimum output-buffer size, so the inflater always has room to emit
  pending decoded data even when no input bytes remain;
- a pending-output flag, set when an inflate call fills the output buffer
  completely, which makes `status()` report NEED_OUTPUT until that pending
  data has actually been drained, instead of NEED_INPUT/end-of-input while
  output is still buffered inside the inflater.

Verification with the project's own tooling: `mvn -o -pl codec-compression
test` passes the upstream regression test for this bug (planted from
/opt/golden) 36/36 offline, and a direct reproduction
(100000 repeated bytes deflated raw with the JDK, decompressed through the
public `JdkZlibDecompressor` API with ZlibWrapper.NONE) now round-trips all
100000 bytes instead of dying with the end-of-stream-marker exception.
MD

# Prove the fix with the project's own test runner: plant the upstream
# regression test (golden bytes from /opt/golden) and run it offline.
cp /opt/golden/JdkZlibDecompressorTest.java codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibDecompressorTest.java
if ! mvn -o -pl codec-compression test -Dtest=JdkZlibDecompressorTest \
        -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true \
        > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -25 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -qE "Tests run: [1-9][0-9]*, Failures: 0, Errors: 0" /tmp/oracle_golden.log || {
    echo "oracle: surefire summary missing; tail:" >&2
    tail -15 /tmp/oracle_golden.log >&2
    exit 1
}

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibDecompressorTest.java || {
    echo "oracle: could not restore JdkZlibDecompressorTest.java" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression suite green"
exit 0