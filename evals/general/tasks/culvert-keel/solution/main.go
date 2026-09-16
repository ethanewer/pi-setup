// culvert-keel registry service.
//
// Middleware chain implemented on the Go standard library's classic net
// package:
//   1. request-ID assignment/echo (X-Request-ID, UUIDv4 when absent),
//   2. bearer-token auth against the fixture key file,
//   3. per-principal token-bucket rate limiting,
//   4. structured JSON access logging (one object per request).
// In front of two JSON endpoints: GET/healthz and GET|POST /api/v1/registry.
package main

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// config
// ---------------------------------------------------------------------------

type RateLimitCfg struct {
	Capacity     int     `json:"capacity"`
	RefillPerSec float64 `json:"refill_per_sec"`
}

type ServerConfig struct {
	Host        string       `json:"host"`
	TokensFile  string       `json:"tokens_file"`
	EntriesFile string       `json:"entries_file"`
	LogFile     string       `json:"log_file"`
	RateLimit   RateLimitCfg `json:"rate_limit"`
}

type Entry struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type EntriesFile struct {
	Entries []Entry `json:"entries"`
}

// ---------------------------------------------------------------------------
// token bucket (per principal)
// ---------------------------------------------------------------------------

type Bucket struct {
	mu       sync.Mutex
	tokens   float64
	last     time.Time
	capacity float64
	refill   float64
}

func newBucket(capacity float64, refill float64) *Bucket {
	return &Bucket{tokens: capacity, last: time.Now(), capacity: capacity, refill: refill}
}

// take reports whether one token was available and consumed it.
func (b *Bucket) take(now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	elapsed := now.Sub(b.last).Seconds()
	b.tokens += elapsed * b.refill
	if b.tokens > b.capacity {
		b.tokens = b.capacity
	}
	b.last = now
	if b.tokens >= 1 {
		b.tokens -= 1
		return true
	}
	return false
}

func (b *Bucket) waitSeconds(now time.Time) float64 {
	b.mu.Lock()
	defer b.mu.Unlock()
	elapsed := now.Sub(b.last).Seconds()
	b.tokens += elapsed * b.refill
	if b.tokens > b.capacity {
		b.tokens = b.capacity
	}
	need := 1 - b.tokens
	if need <= 0 {
		return 0
	}
	return need / b.refill
}

// ---------------------------------------------------------------------------
// app state
// ---------------------------------------------------------------------------

type App struct {
	cfgDir  string
	cfg     ServerConfig
	mu      sync.Mutex
	tokens  map[string]string // token -> principal
	entries []Entry
	buckets map[string]*Bucket // principal -> bucket
	logFile *os.File
}

func resolvePath(cfgDir, p string) string {
	if strings.HasPrefix(p, "/") {
		return p
	}
	return cfgDir + "/" + p
}

func loadConfig(cfgDir string) (*App, error) {
	raw, err := os.ReadFile(cfgDir + "/server.json")
	if err != nil {
		return nil, fmt.Errorf("server.json: %w", err)
	}
	var cfg ServerConfig
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("server.json: %w", err)
	}
	if cfg.Host == "" {
		cfg.Host = "127.0.0.1"
	}
	if cfg.RateLimit.Capacity < 1 {
		cfg.RateLimit.Capacity = 1
	}
	if cfg.RateLimit.RefillPerSec <= 0 {
		cfg.RateLimit.RefillPerSec = 1
	}
	app := &App{cfgDir: cfgDir, cfg: cfg, tokens: map[string]string{}, buckets: map[string]*Bucket{}}

	keysRaw, err := os.ReadFile(resolvePath(cfgDir, cfg.TokensFile))
	if err != nil {
		return nil, fmt.Errorf("keys file: %w", err)
	}
	for _, line := range strings.Split(string(keysRaw), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		eq := strings.Index(line, "=")
		if eq <= 0 {
			continue
		}
		tok := strings.TrimSpace(line[:eq])
		pri := strings.TrimSpace(line[eq+1:])
		if tok != "" && pri != "" {
			if _, seen := app.tokens[tok]; !seen {
				app.tokens[tok] = pri
			}
		}
	}

	entRaw, err := os.ReadFile(resolvePath(cfgDir, cfg.EntriesFile))
	if err != nil {
		return nil, fmt.Errorf("entries file: %w", err)
	}
	var ef EntriesFile
	if err := json.Unmarshal(entRaw, &ef); err != nil {
		return nil, fmt.Errorf("entries file: %w", err)
	}
	app.entries = ef.Entries

	lf, err := os.OpenFile(cfg.LogFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("log file: %w", err)
	}
	app.logFile = lf
	return app, nil
}

func (a *App) bucketFor(principal string) *Bucket {
	a.mu.Lock()
	defer a.mu.Unlock()
	b, ok := a.buckets[principal]
	if !ok {
		b = newBucket(float64(a.cfg.RateLimit.Capacity), a.cfg.RateLimit.RefillPerSec)
		a.buckets[principal] = b
	}
	return b
}

func (a *App) logLine(rid, method, path string, status int, principal *string) {
	type rec struct {
		Ts        int64   `json:"ts"`
		RequestID string  `json:"request_id"`
		Method    string  `json:"method"`
		Path      string  `json:"path"`
		Status    int     `json:"status"`
		Principal *string `json:"principal"`
	}
	out, err := json.Marshal(rec{Ts: time.Now().Unix(), RequestID: rid, Method: method, Path: path, Status: status, Principal: principal})
	if err != nil {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.logFile != nil {
		fmt.Fprintln(a.logFile, string(out))
	}
}

// ---------------------------------------------------------------------------
// http helpers
// ---------------------------------------------------------------------------

func writeResp(conn net.Conn, status int, statusText string, headers map[string]string, body []byte) {
	var sb strings.Builder
	sb.WriteString("HTTP/1.1 " + strconv.Itoa(status) + " " + statusText + "\r\n")
	sb.WriteString("Content-Type: application/json\r\n")
	sb.WriteString("Content-Length: " + strconv.Itoa(len(body)) + "\r\n")
	for k, v := range headers {
		sb.WriteString(k + ": " + v + "\r\n")
	}
	sb.WriteString("Connection: close\r\n\r\n")
	conn.Write([]byte(sb.String()))
	conn.Write(body)
}

func jsonBody(v interface{}) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		return []byte(`{"error":"internal"}`)
	}
	return b
}

func isPrintable(s string) bool {
	for _, r := range s {
		if r < 0x20 || r > 0x7e {
			return false
		}
	}
	return true
}

func newUUID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		ts := time.Now().UnixNano()
		for i := 0; i < 16; i++ {
			b[i] = byte(ts >> (8 * uint(i%8)))
		}
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b)
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

// ---------------------------------------------------------------------------
// routing + middleware
// ---------------------------------------------------------------------------

type Response struct {
	status    int
	text      string
	headers   map[string]string
	body      []byte
	principal *string
}

func (a *App) handleReq(method, target string, headers map[string]string, body []byte) *Response {
	rawPath := target
	if i := strings.Index(target, "?"); i >= 0 {
		rawPath = target[:i]
	}
	path := strings.TrimSuffix(rawPath, "/")
	if path == "" {
		path = "/"
	}

	rid := ""
	if v, ok := headers["x-request-id"]; ok && len(v) > 0 && len(v) <= 128 && isPrintable(v) {
		rid = v
	}
	if rid == "" {
		rid = newUUID()
	}

	if path == "/healthz" {
		if method != "GET" {
			return &Response{status: 405, text: "Method Not Allowed", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "method_not_allowed"})}
		}
		return &Response{status: 200, text: "OK", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]interface{}{"ok": true})}
	}

	if !strings.HasPrefix(path, "/api/") {
		return &Response{status: 404, text: "Not Found", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "not_found"})}
	}

	// --- middleware 2: bearer-token auth ---
	principal, _ := a.authenticate(headers)
	if principal == "" {
		return &Response{status: 401, text: "Unauthorized", headers: map[string]string{"WWW-Authenticate": "Bearer", "X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "unauthorized"})}
	}

	// --- middleware 3: per-principal token bucket ---
	bucket := a.bucketFor(principal)
	now := time.Now()
	if !bucket.take(now) {
		wait := bucket.waitSeconds(now)
		ra := int(wait) + 1
		return &Response{status: 429, text: "Too Many Requests", headers: map[string]string{"Retry-After": strconv.Itoa(ra), "X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "rate_limited"}), principal: &principal}
	}

	switch path {
	case "/api/v1/registry":
		if method == "GET" {
			a.mu.Lock()
			entries := make([]Entry, len(a.entries))
			copy(entries, a.entries)
			a.mu.Unlock()
			return &Response{status: 200, text: "OK", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]interface{}{"principal": principal, "entries": entries}), principal: &principal}
		}
		if method == "POST" {
			var in Entry
			if err := json.Unmarshal(body, &in); err != nil || in.Name == "" {
				return &Response{status: 400, text: "Bad Request", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "bad_json"}), principal: &principal}
			}
			a.mu.Lock()
			for _, e := range a.entries {
				if e.Name == in.Name {
					a.mu.Unlock()
					return &Response{status: 409, text: "Conflict", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "duplicate_name"}), principal: &principal}
				}
			}
			a.entries = append(a.entries, in)
			a.mu.Unlock()
			return &Response{status: 201, text: "Created", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]interface{}{"added": in, "principal": principal}), principal: &principal}
		}
		return &Response{status: 405, text: "Method Not Allowed", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "method_not_allowed"}), principal: &principal}
	}
	return &Response{status: 404, text: "Not Found", headers: map[string]string{"X-Request-ID": rid}, body: jsonBody(map[string]string{"error": "not_found"}), principal: &principal}
}

func (a *App) authenticate(headers map[string]string) (string, string) {
	ah := headers["authorization"]
	if !strings.HasPrefix(strings.ToLower(ah), "bearer ") {
		return "", ""
	}
	tok := strings.TrimSpace(ah[len("bearer "):])
	if tok == "" {
		return "", ""
	}
	a.mu.Lock()
	pri, ok := a.tokens[tok]
	a.mu.Unlock()
	if !ok {
		return "", ""
	}
	return pri, tok
}

func (a *App) handleConn(conn net.Conn) {
	defer conn.Close()
	br := bufio.NewReader(conn)

	line, err := br.ReadString('\n')
	if err != nil {
		return
	}
	line = strings.TrimSpace(line)
	parts := strings.Fields(line)
	if len(parts) < 2 {
		return
	}
	method := strings.ToUpper(parts[0])
	target := parts[1]

	headers := map[string]string{}
	contentLength := 0
	for {
		l, err := br.ReadString('\n')
		if err != nil {
			return
		}
		l = strings.TrimRight(l, "\r\n")
		if l == "" {
			break
		}
		i := strings.Index(l, ":")
		if i <= 0 {
			continue
		}
		k := strings.ToLower(strings.TrimSpace(l[:i]))
		v := strings.TrimSpace(l[i+1:])
		headers[k] = v
		if k == "content-length" {
			if n, err := strconv.Atoi(v); err == nil {
				contentLength = n
			}
		}
	}

	var body []byte
	if contentLength > 0 {
		if contentLength > 1<<20 {
			contentLength = 1 << 20
		}
		body = make([]byte, contentLength)
		if _, err := io.ReadFull(br, body); err != nil {
			return
		}
	}

	resp := a.handleReq(method, target, headers, body)
	rid := resp.headers["X-Request-ID"]
	if rid == "" {
		rid = newUUID()
	}
	logPath := strings.SplitN(target, "?", 2)[0]
	writeResp(conn, resp.status, resp.text, resp.headers, resp.body)
	a.logLine(rid, method, logPath, resp.status, resp.principal)
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: server CONFIG_DIR PORT")
		os.Exit(2)
	}
	cfgDir := os.Args[1]
	port := os.Args[2]
	app, err := loadConfig(cfgDir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config error:", err)
		os.Exit(1)
	}
	addr := app.cfg.Host + ":" + port
	ln, err := net.Listen("tcp4", addr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "listen error:", err)
		os.Exit(1)
	}
	fmt.Println("listening on", addr, "log", app.cfg.LogFile)
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go app.handleConn(conn)
	}
}