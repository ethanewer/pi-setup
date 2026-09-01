FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir openpyxl pandas

COPY files/ /app/

RUN mkdir -p /logs/verifier && chmod -R a+r /app