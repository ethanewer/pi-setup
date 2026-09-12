// Hidden case for cistern-cleat: robustness across the concatenated header
// value. A malformed (non-IP) first line must not mask a valid later line,
// and a later line that only carries the trusted proxy must not change the
// result that the single-line path already produced today.

package gin

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHiddenInvalidFirstLineDoesNotMaskLater(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// A garbage first line (edge proxy received an empty/malformed value)
	// plus a valid second line appended by the last hop.
	c.Request.Header.Add("X-Forwarded-For", "not-an-ip")
	c.Request.Header.Add("X-Forwarded-For", "198.51.100.1")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	assert.Equal(t, "198.51.100.1", c.ClientIP())
}

func TestHiddenLaterLineOnlyTrustedIsNoRegression(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// Same observable result as the single-line path: the rightmost untrusted
	// address stays 198.51.100.2 even though a later line only contains the
	// trusted platform proxy address.
	c.Request.Header.Add("X-Forwarded-For", "198.51.100.2, 192.0.2.1")
	c.Request.Header.Add("X-Forwarded-For", localhostIP)
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	assert.Equal(t, "192.0.2.1", c.ClientIP())
}