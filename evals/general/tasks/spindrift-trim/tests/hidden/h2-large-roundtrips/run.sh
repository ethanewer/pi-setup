#!/bin/bash
# Hidden case h2 (spindrift-trim): real HTTP server round trips at sizes and
# content types the upstream regression test does not use (7, 4096 and
# 1,048,576 bytes; application/x-custom), asserting the declared Content-Length,
# the preserved Content-Type and the integrity (byte count) of the received
# body through real HTTP framing.
set -u
TREE=${TREE:?TREE must point at a planted copy of the agent fixed tree}
cat > "$TREE/render/h2_test.go" <<'EOF'
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

func TestHiddenLargeRoundTrips(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		size, err := strconv.Atoi(r.URL.Query().Get("size"))
		assert.NoError(t, err)
		data := Data{
			ContentType: "application/x-custom",
			Data:        make([]byte, size),
		}
		assert.NoError(t, data.Render(w))
	}))
	t.Cleanup(srv.Close)

	for _, size := range []int{7, 4096, 1_048_576} {
		t.Run(strconv.Itoa(size), func(t *testing.T) {
			resp, err := http.Get(srv.URL + "?size=" + strconv.Itoa(size))
			require.NoError(t, err)
			defer resp.Body.Close()

			assert.Equal(t, "application/x-custom", resp.Header.Get("Content-Type"))
			assert.Equal(t, strconv.Itoa(size), resp.Header.Get("Content-Length"))

			actual, err := io.Copy(io.Discard, resp.Body)
			require.NoError(t, err)
			assert.EqualValues(t, size, actual)
		})
	}
}
EOF
( cd "$TREE" && go test -v github.com/gin-gonic/gin/render \
      -test.run 'TestHiddenLargeRoundTrips' >/tmp/h2.out 2>&1 )
rc=$?
rm -f "$TREE/render/h2_test.go"
cat /tmp/h2.out
[ "$rc" -eq 0 ] || exit 1
grep -q -- '--- PASS: TestHiddenLargeRoundTrips' /tmp/h2.out || exit 1
exit 0