// Hidden case for cistern-cleat: a three-line proxy chain.
// Two forward proxies in front of the trusted platform proxy, each appending
// its own X-Forwarded-For line. The upstream regression test only covers two
// lines (and a single line); these cases use three separate header lines and
// a mid-line multi-valued list.

package gin

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHiddenChainThreeLines(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// client -> proxy A -> proxy B -> trusted platform proxy (localhostIP);
	// each hop appends its own X-Forwarded-For line with surrounding spaces.
	c.Request.Header.Add("X-Forwarded-For", "10.10.0.1")
	c.Request.Header.Add("X-Forwarded-For", "192.168.1.1")
	c.Request.Header.Add("X-Forwarded-For", "  172.16.0.1   ")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	// The rightmost untrusted address seen across ALL lines is 172.16.0.1.
	assert.Equal(t, "172.16.0.1", c.ClientIP())
}

func TestHiddenMidLineMultiValue(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// The first line already carries a two-address list, the second line was
	// appended later by the proxy that actually talked to the platform proxy.
	c.Request.Header.Add("X-Forwarded-For", "203.0.113.1, " + localhostIP)
	c.Request.Header.Add("X-Forwarded-For", "198.51.100.2")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	assert.Equal(t, "198.51.100.2", c.ClientIP())
}

func TestHiddenTrustedBetweenLines(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/test", nil)
	// A trusted hop sits between two untrusted addresses across separate lines.
	c.Request.Header.Add("X-Forwarded-For", "203.0.113.1")
	c.Request.Header.Add("X-Forwarded-For", localhostIP)
	c.Request.Header.Add("X-Forwarded-For", "203.0.113.9")
	c.Request.RemoteAddr = localhostIP + ":1234"

	c.engine.ForwardedByClientIP = true
	c.engine.RemoteIPHeaders = []string{"X-Forwarded-For"}
	_ = c.engine.SetTrustedProxies([]string{localhostIP})

	assert.Equal(t, "203.0.113.9", c.ClientIP())
}