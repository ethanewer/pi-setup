// Hidden case for cistern-cleat: the bug also affects alternative trusted
// headers configured through RemoteIPHeaders (X-Real-IP), and survives when
// the first configured header is absent but a later one carries several lines.

package gin

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHiddenRealIPTwoLines(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// Two X-Real-IP lines, as appended by a chain of two proxies.
	c.Request.Header.Add("X-Real-IP", "8.8.8.8")
	c.Request.Header.Add("X-Real-IP", "9.9.9.9")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Real-IP"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	assert.Equal(t, "9.9.9.9", c.ClientIP())
}

func TestHiddenRealIPWithDefaultHeaderOrder(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// X-Forwarded-For is absent: validation falls through to X-Real-IP, which
	// carries two lines coming from a two-hop chain.
	c.Request.Header.Add("X-Real-IP", "198.51.100.3")
	c.Request.Header.Add("X-Real-IP", "198.51.100.4")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For", "X-Real-IP"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	assert.Equal(t, "198.51.100.4", c.ClientIP())
}