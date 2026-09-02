FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir protobuf grpcio-tools

COPY files/schemas/person.proto /app/schemas/person.proto

RUN python3 -m grpc_tools.protoc -I/app/schemas --python_out=/app /app/schemas/person.proto