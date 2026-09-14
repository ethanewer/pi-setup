package gin

import (
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
)

// Hidden case: the user-visible symptom through the real router. With
// RedirectFixedPath on, a request that matches no route triggers the
// case-insensitive fixed-path lookup. On this mixed layout (static leaf
// and param route under /doc) the lookup panicked and killed the process;
// after the fix it must answer with a redirect or the normal 404 and the
// process must stay alive. The upstream regression tests exercise the
// tree-level lookup API only, not a full request.

func TestHiddenCaseRouter(t *testing.T) {
	router := New()
	router.RedirectFixedPath = true
	router.GET("/doc/:ver/guide", func(c *Context) {
		c.String(http.StatusOK, "guide")
	})
	router.GET("/doc/stable/guide", func(c *Context) {
		c.String(http.StatusOK, "stable")
	})

	// exact match: 200
	w := PerformRequest(router, http.MethodGet, "/doc/stable/guide")
	assert.Equal(t, http.StatusOK, w.Code)

	// wrong case on the static leaf: 301 redirect to the canonical path
	w = PerformRequest(router, http.MethodGet, "/DOC/STABLE/GUIDE")
	assert.Equal(t, http.StatusMovedPermanently, w.Code)
	assert.Equal(t, "/doc/stable/guide", w.Header().Get("Location"))

	// wrong case on a param value: still a 301 via the param fallback, not a crash
	w = PerformRequest(router, http.MethodGet, "/DOC/42/GUIDE")
	assert.Equal(t, http.StatusMovedPermanently, w.Code)

	// a prefix that exists in the tree but has no handler: 404, process alive
	w = PerformRequest(router, http.MethodGet, "/doc/stable")
	assert.Equal(t, http.StatusNotFound, w.Code)
	w = PerformRequest(router, http.MethodGet, "/doc/nope")
	assert.Equal(t, http.StatusNotFound, w.Code)

	// param value through the router still reaches the handler
	w = PerformRequest(router, http.MethodGet, "/doc/42/guide")
	assert.Equal(t, http.StatusOK, w.Code)

	// longer path beyond the static leaf: 404, process alive
	w = PerformRequest(router, http.MethodGet, "/doc/stable/guide/more")
	assert.Equal(t, http.StatusNotFound, w.Code)
}