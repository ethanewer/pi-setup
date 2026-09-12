// copy_rich_errors_test.go -- hidden case for bracket-cable (1 of 3).
//
// Exercises Context.Copy() with a richer error set than the upstream
// regression test uses: several errors, each with its own message, with
// type flags and metadata attached, whose order must survive the copy,
// plus reverse-direction isolation (mutating the ORIGINAL after the copy
// must not affect the copy -- only copy-side mutation is covered upstream).
package gin

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHiddenCopyRichErrors(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/", nil)

	_ = c.Error(errors.New("first: public")).SetType(ErrorTypePublic)
	_ = c.Error(errors.New("second: private")).SetType(ErrorTypePrivate).
		SetMeta("annotation")
	_ = c.Error(errors.New("third: public")).SetType(ErrorTypePublic)
	_ = c.Error(errors.New("fourth: public")).SetType(ErrorTypePublic)

	cp := c.Copy()

	// same errors, same order, same flags and metadata
	assert.Len(t, cp.Errors, 4)
	assert.Equal(t, "first: public", cp.Errors[0].Error())
	assert.Equal(t, ErrorTypePublic, cp.Errors[0].Type)
	assert.Equal(t, "second: private", cp.Errors[1].Error())
	assert.Equal(t, ErrorTypePrivate, cp.Errors[1].Type)
	assert.Equal(t, "annotation", cp.Errors[1].Meta)
	assert.Equal(t, "third: public", cp.Errors[2].Error())
	assert.Equal(t, ErrorTypePublic, cp.Errors[2].Type)
	assert.Equal(t, "fourth: public", cp.Errors[3].Error())
	assert.Equal(t, ErrorTypePublic, cp.Errors[3].Type)

	// reverse-direction isolation: what happens on the original after the
	// copy must not leak into the snapshot
	_ = c.Error(errors.New("fifth: after-copy"))
	assert.Len(t, c.Errors, 5)
	assert.Len(t, cp.Errors, 4)
}