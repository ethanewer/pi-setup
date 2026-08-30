FROM bench-base:python-3.12

# Libraries for the dataset fetcher and the verifier's parquet checks.
RUN pip install --no-cache-dir pandas pyarrow requests

WORKDIR /app

COPY files/ /app/

RUN chmod +x /app/entrypoint.sh /app/object_server.py

ENTRYPOINT ["/app/entrypoint.sh"]
