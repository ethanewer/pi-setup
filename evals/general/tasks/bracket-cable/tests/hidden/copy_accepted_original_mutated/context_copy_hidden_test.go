// copy_accepted_original_mutated_test.go -- hidden case for bracket-cable (2 of 3).
//
// Exercises Context.Copy() over the negotiated media-type list in a shape the
// upstream regression test does not use: THREE formats negotiated in a single
// SetAccepted call (upstream uses two calls of two formats), and the
// reverse-direction mutation (the ORIGINAL's accepted list is renegotiated
// after the copy; the snapshot must keep the originally negotiated set).
// Also covers the mixed state upstream's nil-test does not: errors were
// recorded but no formats were ever negotiated, so the copy must carry the
// errors while Accepted stays nil.
package gin

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHiddenCopyAcceptedThenOriginalRenegotiates(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/", nil)
	c.SetAccepted("application/json", "text/html", "text/plain")

	cp := c.Copy()

	// snapshot carries all three negotiated formats, in order
	assert.Equal(t, []string{"application/json", "text/html", "text/plain"}, cp.Accepted)

	// renegotiating on the ORIGINAL after the copy must not touch the snapshot
	c.SetAccepted("image/png")
	assert.Equal(t, []string{"image/png"}, c.Accepted)
	assert.Equal(t, []string{"application/json", "text/html", "text/plain"}, cp.Accepted)
}

func TestHiddenCopyErrorsButNoAcceptedStaysNil(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/", nil)
	_ = c.Error(errors.New("stored error"))

	cp := c.Copy()

	assert.Len(t, cp.Errors, 1)
	assert.Equal(t, "stored error", cp.Errors[0].Error())
	// Accepted was never negotiated: the copy must still have no Accepted
	// list (it must not fabricate an empty one and it must not lose the
	// errors in the attempt).
	assert.Nil(t, cp.Accepted)
}