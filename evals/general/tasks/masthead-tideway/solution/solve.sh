#!/bin/bash
# Oracle for masthead-tideway: applies the upstream fix to the real
# prometheus/prometheus tree at /app/src (the compressed response writer must
# remove a handler-set Content-Length at the point the compressed stream is
# actually produced - Write/WriteHeader/Close - instead of only at writer
# construction time), writes /app/repro.sh and /app/summary.md, then proves
# the work: the reproduction must fail against a scratch copy of the tree
# with the pre-fix code restored and must pass against the fixed tree, and
# the whole httputil package suite must stay green. Reads only /app,
# /solution and /opt; never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the stale-Content-Length fix"

# Pristine pre-fix scratch copy, built from the pinned commit's own blob.
PREFIX=/tmp/prefixcheck
rm -rf "$PREFIX"
cp -a /app/src "$PREFIX"
git -C "$PREFIX" show HEAD:util/httputil/compression.go \
    > "$PREFIX/util/httputil/compression.go" \
 || { echo "oracle: could not restore pre-fix compression.go" >&2; exit 1; }

echo "oracle: writing /app/repro.sh"
cat > /app/repro.sh <<'REPRO'
#!/bin/bash
# Failing reproduction for masthead-tideway: a handler-set Content-Length
# survives response compression and truncates the client's read, so the
# decompressor errors out ("unexpected EOF").
# Usage: /app/repro.sh [REPO_DIR]    (defaults to /app/src)
# Contract: plant a temporary V test in the affected package's test dir, run
# the project's own runner on exactly that test, print its output, scrub the
# temp file, and exit 0 iff the body arrived intact.
set -u
REPO="${1:-/app/src}"
[ -d "$REPO" ] || { echo "repro: no such repo directory: $REPO" >&2; exit 2; }
TESTFILE="$REPO/util/httputil/repro_masthead_contentlength_test.go"
rm -f "$TESTFILE"
cat > "$TESTFILE" <<'VEOF'
package httputil

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/klauspost/compress/gzip"
	"github.com/stretchr/testify/require"
)

func TestReproMasthead_StaleContentLength(t *testing.T) {
	srv := httptest.NewServer(CompressionHandler{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		part1 := strings.Repeat("repro-payload", 500)
		part2 := strings.Repeat("second-chunk", 250)
		w.Header().Set("Content-Length", strconv.Itoa(len(part1)+len(part2)))
		w.Write([]byte(part1))
		w.Write([]byte(part2))
	})})
	defer srv.Close()

	req, err := http.NewRequest(http.MethodGet, srv.URL, http.NoBody)
	require.NoError(t, err)
	req.Header.Set(acceptEncodingHeader, gzipEncoding)
	transport := &http.Transport{DisableCompression: true}
	client := &http.Client{Transport: transport}
	resp, err := client.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	reader, err := gzip.NewReader(resp.Body)
	require.NoError(t, err, "unexpected error while creating the gzip reader")
	defer reader.Close()
	body, err := io.ReadAll(reader)
	require.NoError(t, err, "unexpected EOF while decoding the compressed body")
	expected := strings.Repeat("repro-payload", 500) + strings.Repeat("second-chunk", 250)
	require.Equal(t, expected, string(body), "decoded body does not match what the handler wrote")
}
VEOF
trap 'rm -f "$TESTFILE"' EXIT
( cd "$REPO" && go test -v ./util/httputil -run TestReproMasthead_StaleContentLength )
exit $?
REPRO
chmod +x /app/repro.sh

echo "oracle: proving both directions"
bash /app/repro.sh "$PREFIX" > /tmp/oracle_prefix.log 2>&1
rcp=$?
if [ "$rcp" -eq 0 ]; then
    echo "oracle: repro did NOT fail on the pre-fix tree (exit $rcp); stdout:" >&2
    head -20 /tmp/oracle_prefix.log >&2
    exit 1
fi
echo "oracle: repro fails on the pre-fix tree as expected (exit $rcp)"

bash /app/repro.sh /app/src > /tmp/oracle_fixed.log 2>&1
rcf=$?
if [ "$rcf" -ne 0 ]; then
    echo "oracle: repro FAILED on the fixed tree (exit $rcf); stdout:" >&2
    head -30 /tmp/oracle_fixed.log >&2
    exit 1
fi
echo "oracle: repro passes on the fixed tree"

# The tree must contain exactly the one source-file change, per the grading
# scope rule.
status=$(git status --porcelain)
if [ "$status" != " M util/httputil/compression.go" ]; then
    echo "oracle: tree not clean besides the fix; status:" >&2
    echo "$status" >&2
    exit 1
fi

# Prove nothing else broke: whole affected-package suite (without the golden
# test, which upstream added with the fix and which the verifier plants).
if ! go test -v ./util/httputil > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: whole httputil package suite did not pass; tail:" >&2
    tail -40 /tmp/oracle_suite.log >&2
    exit 1
fi
echo "oracle: whole httputil package suite green:"
grep -E -- "^ok|PASS" /tmp/oracle_suite.log | tail -8

rm -rf "$PREFIX"

cat > /app/summary.md <<'MD'
# masthead-tideway — fix summary

## Symptom

HTTP API responses compressed on the wire (gzip or deflate) carried a stale
`Content-Length` header whenever the API handler set that header itself: the
value advertised the byte count of the UNCOMPRESSED body. Clients that trust
the header read exactly that many bytes, truncated the compressed stream,
and failed to decompress with errors like "unexpected EOF".

## Root cause

The response-compression layer wraps the handler's response writer in a
compressed writer at construction time (when the request's Accept-Encoding
is inspected). The code tried to avoid the stale-length problem by deleting
`Content-Length` from the writer's headers AT CONSTRUCTION TIME — i.e.
BEFORE the handler had a chance to set the header. A handler that sets
`Content-Length` itself (which the base HTTP machinery encourages for fixed
bodies) then re-adds it, and nothing ever removed it afterwards, so the
stale uncompressed length reached the wire. Uncompressed ("identity")
responses were unaffected because for them the header is correct.

## Fix

The compressed writer now removes a handler-set `Content-Length` at the
actual production points — when the body stream is first written, when a
status line is written, and when the writer is closed — and only for the
gzip and deflate writers that actually transform the byte count. The
constructor-time delete is gone, so the framework's own length accounting
(and the identity path) is left untouched.

## Verification

- `/app/repro.sh` (with a temporary multi-write gzip test through the
  project's own HTTP client/decompressor) FAILS on the pre-fix code and
  PASSES on the fixed tree.
- The whole `util/httputil` package test suite passes on the fixed tree.
MD
test -s /app/summary.md || { echo "oracle: summary.md missing" >&2; exit 1; }

echo "oracle: done"