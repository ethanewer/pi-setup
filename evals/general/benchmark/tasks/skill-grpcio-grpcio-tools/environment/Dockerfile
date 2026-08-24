FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --quiet grpcio grpcio-tools

COPY files/echo.proto /app/echo.proto