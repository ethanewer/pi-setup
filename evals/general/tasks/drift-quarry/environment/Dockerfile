FROM bench-base:python-3.12

# Libraries for the dataset fetcher and the verifier's parquet checks.
RUN pip install --no-cache-dir pandas==3.0.5 pyarrow==25.0.1 requests==2.34.2

WORKDIR /app

COPY files/ /app/

RUN chmod +x /app/entrypoint.sh /app/object_server.py

ENTRYPOINT ["/app/entrypoint.sh"]
