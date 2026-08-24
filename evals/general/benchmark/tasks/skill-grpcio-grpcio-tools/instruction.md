This task exercises the **grpcio / grpcio-tools** Python ecosystem: generating gRPC stubs from a `.proto` file and using the generated message classes.

The proto file `/app/echo.proto` defines:

```protobuf
syntax = "proto3";
package probe;
message GreetRequest { string name = 1; }
message GreetResponse { string message = 1; }
service GreetService { rpc Greet (GreetRequest) returns (GreetResponse); }
```

`grpcio` and `grpcio-tools` are installed.

1. Generate the Python stubs with grpcio-tools' bundled `protoc`, writing outputs into `/app/gen`:
   ```
   mkdir -p /app/gen
   python3 -m grpc_tools.protoc --proto_path=/app --python_out=/app/gen --grpc_python_out=/app/gen /app/echo.proto
   ```
2. Write a driver `/app/driver.py` that:
   - adds `/app/gen` to `sys.path`,
   - imports the generated `echo_pb2` and `echo_pb2_grpc` modules,
   - builds a `GreetRequest(name="atlantis")`,
   - performs a **serialization round-trip**: `SerializeToString()` then `FromString(...)`,
   - confirms the parsed message's `name` field is still `atlantis`,
   - confirms the generated `echo_pb2_grpc` module defines a `GreetServiceStub` class,
   - prints `OK`.
3. Run the driver and copy its output (`OK`) to `/app/answer.txt` (exactly the string `OK`, nothing else).

The verifier runs the same round-trip using your generated modules in `/app/gen` and checks everything is consistent and that `/app/answer.txt` equals `OK`.