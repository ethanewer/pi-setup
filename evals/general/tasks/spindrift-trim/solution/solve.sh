#!/bin/bash
# Oracle for spindrift-trim: applies the upstream fix to the real gin tree at
# /app/src (render.Data.Render() must write a Content-Length header for a
# non-empty payload before writing the body), writes /app/repro.sh and
# /app/summary.md, then proves the work: the reproduction must pass against the
# fixed tree and must fail against a fresh pristine pre-fix tree rebuilt from
# the pinned parent commit. Reads only /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/data-fix.patch || {
    echo "oracle: data-fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/data-fix.patch
echo "oracle: applied the Content-Length fix to render/data.go"

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction: the framework's raw-data renderer (serving raw bytes
# with a caller-chosen content type) must declare an exact Content-Length for
# a known-size, non-empty payload.
# Contract: honour $GIN_SRC (default /app/src), copy the tree to a scratch dir
# under /tmp, plant a tiny test in the copy's render/, run it through the
# project's own test runner, print everything it prints, exit 0 iff it passed.
set -u
GIN_SRC=${GIN_SRC:-/app/src}
work=$(mktemp -d /tmp/gin-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT

[ -f "$GIN_SRC/go.mod" ] || { echo "GIN_SRC does not look like a gin tree: $GIN_SRC" >&2; exit 1; }
cp -a "$GIN_SRC" "$work/src" || exit 1

cat > "$work/src/render/repro_test.go" <<'EOF'
package render

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReproRawDataMissingContentLength(t *testing.T) {
	// In-process response recorder: the renderer itself must supply the
	// header, nothing else can.
	w := httptest.NewRecorder()
	blob := []byte{0x00, 0x89, 0xff, 0x50, 0x10, 0x00, 0x00, 0x01}
	err := (Data{
		ContentType: "image/webp",
		Data:        blob,
	}).Render(w)
	require.NoError(t, err)
	assert.Equal(t, blob, w.Body.Bytes())
	assert.Equal(t, "image/webp", w.Header().Get("Content-Type"))
	assert.Equal(t, strconv.Itoa(len(blob)), w.Header().Get("Content-Length"))

	// Real HTTP connection, payload too large for incidental framing to
	// provide the length.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data := make([]byte, 250_000)
		assert.NoError(t, (Data{
			ContentType: "application/octet-stream",
			Data:        data,
		}).Render(w))
	}))
	t.Cleanup(srv.Close)

	resp, err := http.Get(srv.URL + "/")
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, "application/octet-stream", resp.Header.Get("Content-Type"))
	assert.Equal(t, "250000", resp.Header.Get("Content-Length"))

	actual, err := io.Copy(io.Discard, resp.Body)
	require.NoError(t, err)
	assert.EqualValues(t, 250_000, actual)
}
EOF

( cd "$work/src" && go test -v github.com/gin-gonic/gin/render \
      -test.run TestReproRawDataMissingContentLength )
rc=$?
exit $rc
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: responses produced with the framework's raw-data renderer (raw bytes
with a caller-chosen content type, e.g. generated images or downloads)
carried no Content-Length header even though the payload size was known
before the first body byte was written. Strict clients, caches and
progress-bar middleware saw the header missing or empty and could refuse
the response, fall back to chunked framing, or fail to size buffers.

Cause: the raw-data renderer's Render() wrote the content type and then the
body but never declared the byte length on the response header.

Change: in the raw-data renderer's Render(), after writing the content type
and before writing the body, set Content-Length to the decimal byte length
when the payload is non-empty:

    if len(r.Data) > 0 {
        w.Header().Set("Content-Length", strconv.Itoa(len(r.Data)))
    }

Verification: /app/repro.sh fails against a pristine pre-fix tree (missing
Content-Length assertion, real HTTP server) and passes against the fixed
tree; the project's own render package test suite (go test
github.com/gin-gonic/gin/render) is green, including the upstream regression
test added with the fix (TestRenderData and TestRenderDataContentLength).
MD
echo "oracle: wrote /app/summary.md"

# Prove the work in both directions with the project's own test machinery.
if ! bash /app/repro.sh > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the fixed tree; out:" >&2
    head -30 /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
grep -q '^ok' /tmp/oracle_repro_fixed.out || {
    echo "oracle: repro fixed-direction did not print a passing go test run" >&2
    exit 1
}

pre=$(mktemp -d /tmp/oracle-prefix.XXXXXX) || exit 1
git archive --format=tar db309081bc5c137b2aa15701ef53f7f19788da25 | tar -x -C "$pre" \
    || { echo "oracle: could not rebuild pristine parent tree" >&2; exit 1; }
if GIN_SRC="$pre" bash /app/repro.sh > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix tree (expected failure)" >&2
    exit 1
fi
rm -rf "$pre"

echo "oracle: fix applied, deliverables written, repro OK on fixed tree and fails on pre-fix tree"
exit 0