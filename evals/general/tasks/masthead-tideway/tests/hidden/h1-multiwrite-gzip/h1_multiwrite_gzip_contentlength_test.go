package httputil

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/klauspost/compress/gzip"
	"github.com/stretchr/testify/require"
)

// Hidden case H1: gzip-compressed response where the handler sets an explicit
// Content-Length up front and then writes the body in multiple chunks after an
// explicit status line. Uses a payload far larger than the upstream test's
// "Hello World!" and a 201 status, so it reaches the same code path from
// inputs the upstream regression test does not use.
func TestHiddenH1_MultiWriteGzipContentLength(t *testing.T) {
	srv := httptest.NewServer(CompressionHandler{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		part1 := strings.Repeat("metric-a", 1000) // 8000 bytes
		part2 := strings.Repeat("metric-b", 500)  // 4000 bytes
		part3 := strings.Repeat("metric-c", 250)  // 2000 bytes
		w.Header().Set("Content-Length", strconv.Itoa(len(part1)+len(part2)+len(part3)))
		w.WriteHeader(http.StatusCreated)
		w.Write([]byte(part1))
		w.Write([]byte(part2))
		w.Write([]byte(part3))
	})})
	defer srv.Close()

	req, err := http.NewRequest(http.MethodGet, srv.URL, http.NoBody)
	require.NoError(t, err)
	req.Header.Set(acceptEncodingHeader, gzipEncoding)
	transport := &http.Transport{DisableCompression: true}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}
	resp, err := client.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode, "unexpected status on response")

	reader, err := gzip.NewReader(resp.Body)
	require.NoError(t, err, "unexpected error while creating the gzip reader")
	defer reader.Close()
	body, err := io.ReadAll(reader)
	require.NoError(t, err, "unexpected EOF while decoding the compressed body")
	expected := strings.Repeat("metric-a", 1000)+strings.Repeat("metric-b", 500)+strings.Repeat("metric-c", 250)
	require.Equal(t, expected, string(body), "decoded body does not match what the handler wrote")
}