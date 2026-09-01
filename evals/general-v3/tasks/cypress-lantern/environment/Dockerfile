FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir flask==3.0.3

COPY files/ /app/
