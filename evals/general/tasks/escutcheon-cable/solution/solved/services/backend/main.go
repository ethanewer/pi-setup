// Cart backend — the Go flagship service that resolves order records.
//
// Implements the repository README observability contract: honours the W3C
// traceparent header forwarded by the frontend, writes structured JSON logs
// (correlation field `trace_id`) to stdout (redirected by up.sh to
// .logs/backend.jsonl), and emits one span per handled request to the
// collector at 127.0.0.1:9100/span.
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

var orders = map[string]map[string]interface{}{}

func randHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// traceparent returns (traceID, parentSpanID) from the header, else "", "".
func traceparent(h string) (string, string) {
	p := strings.Split(h, "-")
	if len(p) == 4 && p[0] == "00" && len(p[1]) == 32 && len(p[2]) == 16 {
		return p[1], p[2]
	}
	return "", ""
}

func jlog(traceID, spanID, parent, msg string, info map[string]interface{}) {
	rec := map[string]interface{}{
		"ts": time.Now().UnixMilli(), "service": "backend",
		"level": "info", "trace_id": traceID, "span_id": spanID,
		"parent_span_id": parent, "msg": msg,
	}
	for k, v := range info {
		rec[k] = v
	}
	b, _ := json.Marshal(rec)
	fmt.Println(string(b))
}

func emitSpan(traceID, spanID, parent, name string, code int, start time.Time) {
	rec := map[string]interface{}{
		"service": "backend", "name": name,
		"trace_id": traceID, "span_id": spanID,
		"parent_span_id": parent, "kind": "server",
		"start_ms": start.UnixMilli(), "end_ms": time.Now().UnixMilli(),
		"status": code, "error": code >= 500,
	}
	b, _ := json.Marshal(rec)
	req, err := http.NewRequest("POST", "http://127.0.0.1:9100/span",
		strings.NewReader(string(b)))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 2 * time.Second}
	if resp, err := client.Do(req); err == nil {
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
}

func handle(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path

	if path == "/health" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(200)
		w.Write([]byte(`{"ok":true}`))
		return
	}

	if strings.HasPrefix(path, "/order/") {
		orderID := strings.TrimPrefix(path, "/order/")
		traceID, parent := traceparent(r.Header.Get("traceparent"))
		if traceID == "" {
			traceID = randHex(16)
		}
		spanID := randHex(8)
		start := time.Now()

		jlog(traceID, spanID, parent, "order.request",
			map[string]interface{}{"order_id": orderID})

		code := 200
		body := []byte(`{}`)
		if orderID == "OR-LOST" {
			code = 500
			body, _ = json.Marshal(map[string]interface{}{
				"error": "upstream_recompute_failed", "id": orderID})
		} else if order, ok := orders[orderID]; ok {
			body, _ = json.Marshal(order)
		} else {
			code = 404
			body, _ = json.Marshal(map[string]interface{}{
				"error": "not_found", "id": orderID})
		}

		emitSpan(traceID, spanID, parent, "backend.order", code, start)
		jlog(traceID, spanID, parent, "order.complete",
			map[string]interface{}{"order_id": orderID, "status": code})

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		w.Write(body)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(404)
	w.Write([]byte(`{"error":"not_found"}`))
}

func main() {
	f, err := os.Open("/app/data/orders.json")
	if err == nil {
		var doc map[string]interface{}
		if json.NewDecoder(f).Decode(&doc) == nil {
			if list, ok := doc["orders"].([]interface{}); ok {
				for _, item := range list {
					if m, ok := item.(map[string]interface{}); ok {
						if id, ok := m["id"].(string); ok {
							orders[id] = m
						}
					}
				}
			}
		}
		f.Close()
	}

	fmt.Println("backend on 127.0.0.1:8100")
	srv := &http.Server{Addr: "127.0.0.1:8100", Handler: http.HandlerFunc(handle)}
	if err := srv.ListenAndServe(); err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
}
