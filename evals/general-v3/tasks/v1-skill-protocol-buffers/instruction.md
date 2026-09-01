# Protocol Buffers serialization

This environment has the Google **Protocol Buffers** runtime installed, and a compiled message module at `/app/person_pb2.py` generated from this proto schema:

```proto
syntax = "proto3";

message Person {
  string name = 1;
  int32  id   = 2;
  string email = 3;
}
```

So you can `import person_pb2` (after adding `/app` to the Python import path) and build `Person` messages with fields `.name`, `.id`, `.email` and serialize them to bytes.

Write a Python program `/app/writer.py` that:

1. Imports `person_pb2`.
2. Creates a `Person` message with fields:
   - `name = "Grace Hopper"`
   - `id = 7`
   - `email = "grace@example.org"`
3. Serializes the message to bytes with `.SerializeToString()` (or `.SerializePartialToString()`).
4. Writes those bytes to the binary file `/app/person.bin`.

Then run `/app/writer.py` so `/app/person.bin` exists. The verifier parses `/app/person.bin` with `person_pb2.Person()` and checks the three fields match exactly.

Note: the verifier runs in the same container and imports `person_pb2` from `/app`, so do **not** move or rename `/app/person_pb2.py`.