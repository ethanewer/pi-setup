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

// Hidden case H3: deflate-compressed EMPTY response where the handler still
// sets Content-Length to 0 and writes an explicit 200 status line. The
// upstream test's empty-body deflate subtest never writes an explicit status,
// so this combination (explicit status + zero-length body + deflate) is not
// covered by the upstream regression test.
func TestHiddenH3_DeflateEmptyBody200ContentLength(t *testing.T) {
	srv := httptest.NewServer(CompressionHandler{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", strconv.Itoa(0))
		w.WriteHeader(http.StatusOK)
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
	require.Equal(t, http.StatusOK, resp.StatusCode, "unexpected status on response")

	reader, err := zlib.NewReader(resp.Body)
	require.NoError(t, err, "unexpected error while creating the zlib reader")
	defer reader.Close()
	body, err := io.ReadAll(reader)
	require.NoError(t, err, "unexpected EOF while decoding the compressed body")
	require.Empty(t, body, "expected an empty body")
}