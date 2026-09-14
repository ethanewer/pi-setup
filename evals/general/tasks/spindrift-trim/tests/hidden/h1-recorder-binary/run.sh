#!/bin/bash
# Hidden case h1 (spindrift-trim): in-process response recorder with a BINARY
# payload containing NUL and 0xff bytes and a distinct content type, and a
# second recorder round trip with an empty payload (the renderer must leave the
# length undeclared for empty bodies, per the fixed contract). The upstream
# regression test's recorder case only uses a 19-byte ASCII payload.
set -u
TREE=${TREE:?TREE must point at a planted copy of the agent fixed tree}
cat > "$TREE/render/h1_test.go" <<'EOF'
package render

import (
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHiddenRecorderBinary(t *testing.T) {
	w := httptest.NewRecorder()
	blob := []byte{0x00, 0x89, 0x50, 0x4e, 0x47, 0x00, 0xff, 0x10, 0x00, 0x7f, 0x80, 0xff}
	err := (Data{
		ContentType: "image/webp",
		Data:        blob,
	}).Render(w)
	require.NoError(t, err)
	assert.Equal(t, blob, w.Body.Bytes())
	assert.Equal(t, "image/webp", w.Header().Get("Content-Type"))
	assert.Equal(t, strconv.Itoa(len(blob)), w.Header().Get("Content-Length"))
}

func TestHiddenRecorderEmptyPayload(t *testing.T) {
	w := httptest.NewRecorder()
	err := (Data{
		ContentType: "application/x-empty",
		Data:        []byte{},
	}).Render(w)
	require.NoError(t, err)
	assert.Equal(t, 0, len(w.Body.Bytes()))
	assert.Equal(t, "application/x-empty", w.Header().Get("Content-Type"))
}
EOF
( cd "$TREE" && go test -v github.com/gin-gonic/gin/render \
      -test.run 'TestHiddenRecorder' >/tmp/h1.out 2>&1 )
rc=$?
rm -f "$TREE/render/h1_test.go"
cat /tmp/h1.out
[ "$rc" -eq 0 ] || exit 1
grep -q -- '--- PASS: TestHiddenRecorderBinary ' /tmp/h1.out || exit 1
grep -q -- '--- PASS: TestHiddenRecorderEmptyPayload ' /tmp/h1.out || exit 1
exit 0