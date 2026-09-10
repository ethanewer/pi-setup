#!/bin/bash
# Oracle for windlass-jetty.
#
# Does the real work: restores the deprecated-field passthrough in the Go
# server, regenerates both Go and Python bindings from the authoritative
# schema, builds the server to prove the repository is consistent, and
# installs the serve.sh deliverable. Never references /tests.
set -euo pipefail

REPO=/app/windlass-dispatch
cd "$REPO"
export PATH="/usr/local/bin:$PATH"

# --- the fix: receipt builder must preserve the deprecated field ------------
cp /solution/main.go.fixed main.go

# --- make every generated artifact agree with the current schema ------------
protoc -I proto --go_out=. --go-grpc_out=. proto/dispatch.proto
python3 -m grpc_tools.protoc -I proto --python_out=client --grpc_python_out=client proto/dispatch.proto

# --- build the server (proves the repository state compiles) ----------------
go build -o windlass-server

# --- install the deliverable serve script -----------------------------------
cp /solution/serve.sh /app/windlass-dispatch/serve.sh
chmod +x /app/windlass-dispatch/serve.sh

echo "oracle: fixed main.go, regenerated bindings, built windlass-server, installed serve.sh"