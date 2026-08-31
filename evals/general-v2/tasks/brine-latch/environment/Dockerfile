FROM bench-base:python-3.12

WORKDIR /app

# Ship the ColdBrine relay tooling and vault. payload.bin is unlinked at
# container start by keeper.py; nothing secret remains on disk.
COPY files/ /app/

RUN mkdir -p /tmp/brine-vault /logs/verifier \
    && chmod +x /app/keeper.py /app/entry.sh \
    && chmod -R a+r /app

ENTRYPOINT ["/app/entry.sh"]
