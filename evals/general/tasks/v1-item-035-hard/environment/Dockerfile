FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir grpcio==1.83.1 grpcio-tools==1.83.1 protobuf==7.36.1

COPY files/ /app/