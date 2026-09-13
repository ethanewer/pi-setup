package security_test

import (
	"testing"

	"github.com/gohugoio/hugo/config"
	"github.com/gohugoio/hugo/config/security"
)

func TestHiddenBallastURLSchemeCase(t *testing.T) {
	pc, err := security.DecodeConfig(config.New())
	if err != nil {
		t.Fatalf("DecodeConfig: %v", err)
	}
	// Mixed-case schemes must not slip past the IP-literal deny rules.
	// The scheme must be case-insensitive: an all-caps HTTP scheme pointing
	// at a loopback/private/CGNAT/reserved address is still blocked, and so
	// is a mixed-case scheme on any non-public literal.
	for _, u := range []string{
		"HTTP://127.0.0.1/",
		"HTTP://10.0.0.1/",
		"hTtP://100.64.0.1/",
		"HTTPS://192.168.1.1:8080/x",
		"HTTP://172.16.9.9:8443/",
		"HtTp://[::ffff:127.0.0.1]/",
	} {
		if err := pc.CheckAllowedHTTPURL(u); err == nil {
			t.Errorf("CheckAllowedHTTPURL(%q): got nil error, want access denied", u)
		} else if !security.IsAccessDenied(err) {
			t.Errorf("CheckAllowedHTTPURL(%q): %v is not an access-denied error", u, err)
		}
	}
	// Mixed-case schemes on ordinary public hosts must stay allowed.
	for _, u := range []string{
		"HTTP://example.com/",
		"https://EXAMPLE.ORG:8443/path",
		"HTTP://www.example.org/sub",
	} {
		if err := pc.CheckAllowedHTTPURL(u); err != nil {
			t.Errorf("CheckAllowedHTTPURL(%q): unexpected deny: %v", u, err)
		}
	}
}