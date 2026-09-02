FROM bench-base:python-3.12

# gRPC toolchain + MLflow tracking server runtime.
# A single pip invocation lets the resolver pick one protobuf version that
# satisfies both grpcio-tools and mlflow.
RUN pip install --no-cache-dir grpcio grpcio-tools mlflow

COPY files/ /app/
WORKDIR /app

# Generate the gRPC stubs (atlas_pb2.py, atlas_pb2_grpc.py) once at build time
# so both the deliverable and the verifier import them from /app.
RUN python3 -m grpc_tools.protoc -I/app --python_out=/app --grpc_python_out=/app /app/atlas.proto