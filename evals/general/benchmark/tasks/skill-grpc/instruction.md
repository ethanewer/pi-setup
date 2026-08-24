A gRPC service is defined by the protobuf file `/app/echo.proto`:

```protobuf
syntax = "proto3";
package probe;
message GreetRequest { string name = 1; }
message GreetResponse { string message = 1; }
service GreetService { rpc Greet (GreetRequest) returns (GreetResponse); }
```

`grpcio` and `grpcio-tools` are installed. Build the Python stubs from the proto, then make a real remote gRPC call to a running server.

1. Generate stubs with grpcio-tools (all outputs into `/app`):
   ```
   python3 -m grpc_tools.protoc --proto_path=/app --python_out=/app --grpc_python_out=/app /app/echo.proto
   ```
2. A gRPC server that implements `GreetService` is provided at `/app/server.py`. It listens on `127.0.0.1:50051` and its `Greet` handler returns a `GreetResponse` whose `message` is `"HELLO, " + request.name.upper()`.
3. Write a client `/app/client.py` that opens a gRPC channel to `127.0.0.1:50051`, creates a `GreetServiceStub`, calls `Greet(GreetRequest(name="neo"))`, and writes the returned `message` to `/app/answer.txt`.
4. Start the server in the background, then run the client.

The expected value of `/app/answer.txt` is exactly:
```
HELLO, NEO
```
The verifier confirms the generated stub modules exist in `/app` and that `/app/answer.txt` holds that exact string.