// Cart backend — the Go flagship service that resolves order records.
//
// This is the SHIPPED baseline. It serves order data from the catalog and
// reports health correctly, but it performs NO distributed tracing and emits
// only plain-text log lines. See the repository README for the observability
// contract that this service and the frontend must satisfy.
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
)

var orders = map[string]map[string]interface{}{}

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
		fmt.Printf("backend order.render id=%s\n", orderID)

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
