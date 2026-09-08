FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir flask==3.1.3

COPY files/ /app/

RUN mkdir -p /logs/verifier
