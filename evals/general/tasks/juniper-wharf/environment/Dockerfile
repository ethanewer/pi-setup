FROM bench-base:python-3.12

# Tools and libraries for the Juniper Wharf infrastructure task:
#   grpc/grpcio-tools/protobuf  -> gRPC codegen for the proto contract
#   boto3/requests/pyOpenSSL    -> object-store clients + TLS metadata
#   pandas/pyarrow              -> reading the parquet splits
RUN pip install --no-cache-dir \
        grpcio==1.83.1 grpcio-tools==1.83.1 protobuf==7.36.1 \
        boto3==1.43.89 requests==2.34.2 pyOpenSSL==26.4.0 \
        pandas==3.0.5 pyarrow==25.0.1

WORKDIR /app
COPY files/ /app/

RUN chmod +x /app/entrypoint.sh /app/object_server.py /app/control_server.py

ENTRYPOINT ["/app/entrypoint.sh"]