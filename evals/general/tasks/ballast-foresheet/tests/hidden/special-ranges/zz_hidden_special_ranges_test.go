package security_test

import (
	"testing"

	"github.com/gohugoio/hugo/config/security"
)

func TestHiddenBallastSpecialRanges(t *testing.T) {
	// CheckAllowedHTTPAddress must deny dest addresses that are never on the
	// public Internet: CGNAT/shared space, IETF assignment, TEST-NET-1..3,
	// benchmarking, reserved space and the IPv6 DOCUMENTATION prefixes.
	pc := security.DefaultConfig
	for _, addr := range []string{
		"100.64.68.25:80",          // CGNAT, RFC 6598.
		"192.0.0.254:80",           // IETF protocol assignment block.
		"192.0.2.200:80",           // TEST-NET-1.
		"198.18.9.9:80",            // Benchmarking.
		"198.51.100.55:80",         // TEST-NET-2.
		"203.0.113.77:80",          // TEST-NET-3.
		"240.1.2.3:80",             // Reserved (240.0.0.0/4).
		"[2001:2::5]:443",          // IPv6 benchmarking 2001:2::/48.
		"[2001:db8:1:2:3:4:5:6]:443", // IPv6 documentation 2001:db8::/32.
	} {
		if err := pc.CheckAllowedHTTPAddress("tcp", addr); err == nil {
			t.Errorf("CheckAllowedHTTPAddress(%q): got nil error, want access denied", addr)
		} else if !security.IsAccessDenied(err) {
			t.Errorf("CheckAllowedHTTPAddress(%q): %v is not an access-denied error", addr, err)
		}
	}
	// Genuinely public addresses stay allowed.
	for _, addr := range []string{
		"8.8.8.8:53",
		"20.205.243.166:443",
		"[2606:4700::1111]:443",
		"[2001:4860:4860::8888]:443",
	} {
		if err := pc.CheckAllowedHTTPAddress("tcp", addr); err != nil {
			t.Errorf("CheckAllowedHTTPAddress(%q): unexpected deny: %v", addr, err)
		}
	}
}