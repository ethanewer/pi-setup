FROM bench-base:python-3.12

WORKDIR /app

# Ship the damaged BrightShard warehouse (transformed inventory.db + WAL witness)
# and the descriptor-keeper tooling. Nothing here is secret-bearing: lost.csv is
# unlinked at container start by keeper.py.
COPY files/ /app/

RUN mkdir -p /tmp/juniper-lockbox /logs/verifier \
    && chmod +x /app/keeper.py /app/entry.sh \
    && chmod -R a+r /app

ENTRYPOINT ["/app/entry.sh"]
