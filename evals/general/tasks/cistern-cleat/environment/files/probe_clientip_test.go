// Reproduction probe for cistern-cleat: a two-proxy chain appends two
// X-Forwarded-For header lines in front of a trusted platform proxy.
//
// Copy this file into /app/src and run:
//
//   cd /app/src && go test -v github.com/gin-gonic/gin -test.run TestProbeClientIPMultiLines
//
// In the buggy checkout ClientIP() reports the FIRST line's leftmost address
// (11.22.33.44) instead of the rightmost untrusted address (55.66.77.88).

package gin

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestProbeClientIPMultiLines(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// Proxy chain: 11.22.33.44 -> 55.66.77.88 -> trusted platform proxy.
	// Each hop appends its own X-Forwarded-For line.
	c.Request.Header.Add("X-Forwarded-For", "11.22.33.44, " + localhostIP)
	c.Request.Header.Add("X-Forwarded-For", "55.66.77.88")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	// The two lines together say the rightmost untrusted address is
	// 55.66.77.88; a single-line X-Forwarded-For with the same list must
	// resolve identically.
	assert.Equal(t, "55.66.77.88", c.ClientIP())
}