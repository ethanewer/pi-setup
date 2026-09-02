FROM bench-base:python-3.12

# Tools and libraries for the Juniper Wharf infrastructure task:
#   grpc/grpcio-tools/protobuf  -> gRPC codegen for the proto contract
#   boto3/requests/pyOpenSSL    -> object-store clients + TLS metadata
#   pandas/pyarrow              -> reading the parquet splits
RUN pip install --no-cache-dir \
        grpcio grpcio-tools protobuf \
        boto3 requests pyOpenSSL \
        pandas pyarrow

WORKDIR /app
COPY files/ /app/

RUN chmod +x /app/entrypoint.sh /app/object_server.py /app/control_server.py

ENTRYPOINT ["/app/entrypoint.sh"]