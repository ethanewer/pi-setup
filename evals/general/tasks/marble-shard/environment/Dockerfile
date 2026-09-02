FROM bench-base:python-3.12

WORKDIR /app

# Ship the cache manifest, the shard keeper tooling, and the visible shard
# payload (unlinked at container start by shardd.py).
COPY files/ /app/

RUN chmod +x /app/shardd.py /app/entry.sh && chmod -R a+r /app

ENTRYPOINT ["/app/entry.sh"]
