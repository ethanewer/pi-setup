FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN mkdir -p /logs/verifier \
    && chmod +x /app/latch_keeper.py /app/entry.sh \
    && chmod -R a+r /app

ENTRYPOINT ["/app/entry.sh"]
