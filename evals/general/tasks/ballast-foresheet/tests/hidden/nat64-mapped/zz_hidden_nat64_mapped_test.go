package security_test

import (
	"testing"

	"github.com/gohugoio/hugo/config"
	"github.com/gohugoio/hugo/config/security"
)

func TestHiddenBallastNAT64AndMapped(t *testing.T) {
	// An IPv4-mapped or NAT64-embedded address carries an inner IPv4 address;
	// the inner address must be evaluated, so embedded/private and embedded
	// special-purpose IPv4 must be denied even though the outer form is
	// global. Embedded public IPv4 stays allowed.
	pc := security.DefaultConfig
	for _, addr := range []string{
		"[64:ff9b::6440:1]:80",            // NAT64-embedded 100.64.0.1 (CGNAT).
		"[64:ff9b::c0a8:101]:80",          // NAT64-embedded 192.168.1.1.
		"[64:ff9b::c000:201]:80",          // NAT64-embedded 192.0.2.1 (TEST-NET-1).
		"[64:ff9b:1::c633:6401]:80",       // NAT64 64:ff9b:1::/48-embedded 198.51.100.1.
		"[::ffff:198.18.0.1]:80",          // IPv4-mapped benchmarking.
		"[::ffff:203.0.113.1]:80",         // IPv4-mapped TEST-NET-3.
		"[::ffff:100.64.68.25]:80",        // IPv4-mapped CGNAT.
	} {
		if err := pc.CheckAllowedHTTPAddress("tcp", addr); err == nil {
			t.Errorf("CheckAllowedHTTPAddress(%q): got nil error, want access denied", addr)
		} else if !security.IsAccessDenied(err) {
			t.Errorf("CheckAllowedHTTPAddress(%q): %v is not an access-denied error", addr, err)
		}
	}
	for _, addr := range []string{
		"[64:ff9b::0808:0808]:53",         // NAT64-embedded 8.8.8.8 (public).
		"[64:ff9b::5db8:d822]:80",         // NAT64-embedded 93.184.216.34 (public).
		"[::ffff:93.184.216.34]:80",       // IPv4-mapped public.
	} {
		if err := pc.CheckAllowedHTTPAddress("tcp", addr); err != nil {
			t.Errorf("CheckAllowedHTTPAddress(%q): unexpected deny: %v", addr, err)
		}
	}
}

// A hostname that the URL policy allows must still be stopped when it
// resolves to an internal address: the text-level check and the dial-time
// address check are both required.
func TestHiddenBallastTextVsResolved(t *testing.T) {
	pc, err := security.DecodeConfig(config.New())
	if err != nil {
		t.Fatalf("DecodeConfig: %v", err)
	}
	if err := pc.CheckAllowedHTTPURL("https://intranet.example.corp/"); err != nil {
		t.Fatalf("CheckAllowedHTTPURL: unexpected deny of text: %v", err)
	}
	if err := security.DefaultConfig.CheckAllowedHTTPAddress("tcp", "172.16.0.7:443"); err == nil {
		t.Errorf("CheckAllowedHTTPAddress(172.16.0.7:443): got nil error, want access denied")
	}
}