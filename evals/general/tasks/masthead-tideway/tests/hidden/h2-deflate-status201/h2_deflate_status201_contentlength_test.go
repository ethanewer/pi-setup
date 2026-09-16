package httputil

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/klauspost/compress/zlib"
	"github.com/stretchr/testify/require"
)

// Hidden case H2: deflate-compressed response where the handler sets an
// explicit Content-Length for a short, unevenly-compressible body and then
// writes it in two chunks after an explicit 201 status line. The upstream
// regression test never combines deflate with an explicit status, multiple
// writes, or a non-"Hello World!" body.
func TestHiddenH2_DeflateStatus201ContentLength(t *testing.T) {
	srv := httptest.NewServer(CompressionHandler{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		part1 := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
		part2 := "fedcba9876543210"
		payload := part1 + part2
		w.Header().Set("Content-Length", strconv.Itoa(len(payload)))
		w.WriteHeader(http.StatusCreated)
		w.Write([]byte(part1))
		w.Write([]byte(part2))
	})})
	defer srv.Close()

	req, err := http.NewRequest(http.MethodGet, srv.URL, http.NoBody)
	require.NoError(t, err)
	req.Header.Set(acceptEncodingHeader, deflateEncoding)
	transport := &http.Transport{DisableCompression: true}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}
	resp, err := client.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, http.StatusCreated, resp.StatusCode, "unexpected status on response")

	reader, err := zlib.NewReader(resp.Body)
	require.NoError(t, err, "unexpected error while creating the zlib reader")
	defer reader.Close()
	body, err := io.ReadAll(reader)
	require.NoError(t, err, "unexpected EOF while decoding the compressed body")
	expected := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" + "fedcba9876543210"
	require.Equal(t, expected, string(body), "decoded body does not match what the handler wrote")
}