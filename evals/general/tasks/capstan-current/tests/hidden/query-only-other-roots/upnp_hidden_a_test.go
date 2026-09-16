// capstan-current hidden case: query-only control URLs with inputs the
// shipped tests do not use.
//
// Both assertions exercise the exact code path the upstream regression test
// hits (replaceRawPath with a bare query string, empty path component) but
// with a different host, port, base path depth and query shape, so passing
// the shipped TestControlURLParsingQueryOnly alone is not sufficient.
//
// At the buggy parent commit both vectors crash with
// "index out of range [0] with length 0"; with the fix they must produce
// exactly the expected URLs.
package upnp

import (
	"net/url"
	"testing"
)

func TestHiddenUpnpCaseOne(t *testing.T) {
	rootURL := "http://10.20.30.40:8080/upnp/igd.xml"
	u, _ := url.Parse(rootURL)
	subject := "?control=urn:upnp-org:service:WANIPConnection:1"
	expected := "http://10.20.30.40:8080/upnp/igd.xml?control=urn:upnp-org:service:WANIPConnection:1"
	replaceRawPath(u, subject)

	if u.String() != expected {
		t.Error("URL normalization of", subject, "failed; expected", expected, "got", u.String())
	}
}

func TestHiddenUpnpCaseTwo(t *testing.T) {
	rootURL := "http://192.168.0.1:80/"
	u, _ := url.Parse(rootURL)
	subject := "?service=WANPPPConnection&port=0"
	expected := "http://192.168.0.1:80/?service=WANPPPConnection&port=0"
	replaceRawPath(u, subject)

	if u.String() != expected {
		t.Error("URL normalization of", subject, "failed; expected", expected, "got", u.String())
	}
}