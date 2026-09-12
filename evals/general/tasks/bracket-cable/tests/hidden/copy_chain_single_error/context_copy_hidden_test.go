// copy_chain_single_error_test.go -- hidden case for bracket-cable (3 of 3).
//
// Exercises Context.Copy() over a case the upstream regression test does not
// use: a SINGLE error, then a copy of the copy (chained snapshots). Both
// generations of snapshot must keep the error, and an error appended to the
// ORIGINAL after the chain must not appear in either snapshot.
package gin

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHiddenCopyChainSingleError(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/", nil)
	_ = c.Error(errors.New("only error"))

	cp := c.Copy()          // first snapshot
	cp2 := cp.Copy()        // snapshot of the snapshot

	// both generations keep exactly the one recorded error
	assert.Len(t, cp.Errors, 1)
	assert.Equal(t, "only error", cp.Errors[0].Error())
	assert.Len(t, cp2.Errors, 1)
	assert.Equal(t, "only error", cp2.Errors[0].Error())

	// mutations after the chain on the original are invisible to both
	_ = c.Error(errors.New("after copy"))
	assert.Len(t, c.Errors, 2)
	assert.Len(t, cp.Errors, 1)
	assert.Len(t, cp2.Errors, 1)
}