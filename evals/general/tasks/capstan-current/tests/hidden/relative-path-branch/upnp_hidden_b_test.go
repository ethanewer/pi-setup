// capstan-current hidden case: the relative-path append branch of the
// control-URL normalization must be unchanged by the fix.
//
// A control URL that is a relative path (no leading slash, but a non-empty
// path component) is appended to the base location's path with the query
// replaced. This exercises the else branch of the fixed guard, which the
// upstream tests do not cover, and guards against a fix that changes
// normalization behaviour beyond the query-only case.
package upnp

import (
	"net/url"
	"testing"
)

func TestHiddenUpnpCaseThree(t *testing.T) {
	rootURL := "http://192.168.243.1:80/igd.xml"
	u, _ := url.Parse(rootURL)
	subject := "relpath?control=WANCommonIFC1"
	expected := "http://192.168.243.1:80/igd.xmlrelpath?control=WANCommonIFC1"
	replaceRawPath(u, subject)

	if u.String() != expected {
		t.Error("URL normalization of", subject, "failed; expected", expected, "got", u.String())
	}
}