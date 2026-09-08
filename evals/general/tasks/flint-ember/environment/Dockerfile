FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir openpyxl==3.1.5 pandas==3.0.5

COPY files/ /app/

RUN mkdir -p /logs/verifier && chmod -R a+r /app