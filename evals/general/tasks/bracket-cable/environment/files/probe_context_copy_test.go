// probe_context_copy_test.go -- scratch reproduction probe for bracket-cable.
//
// This file is NOT part of the gin checkout. To reproduce the reported bug,
// copy it into the repo root next to context_test.go and run:
//
//   cd /app/src && go test -v github.com/gin-gonic/gin -test.run 'TestProbeContextCopy'
//
// On the pinned checkout the probe FAILS (the copy of the context loses the
// error that was attached to the original). When you remove /app/src/probe_context_copy_test.go
// and the trial container is reset, the file is back under /app.
package gin

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestProbeContextCopyRecoversAttachedErrors reproduces the reported bug:
// Context.Copy() promises "a copy of the current context that can be safely
// used outside the request's scope", but the copied context no longer carries
// the errors that were recorded on the original.
func TestProbeContextCopyRecoversAttachedErrors(t *testing.T) {
	c, _ := CreateTestContext(httptest.NewRecorder())
	c.Request, _ = http.NewRequest(http.MethodGet, "/", nil)
	_ = c.Error(errors.New("validation failed"))

	cp := c.Copy()

	// On the buggy tree cp.Errors is nil: the copy behaves as if nothing had
	// ever been recorded on the original context.
	assert.Len(t, cp.Errors, 1)
	assert.Equal(t, "validation failed", cp.Errors[0].Error())
}