# basalt-tide — cipher-oracle key-recovery runtime.
#
# Ships the public cipher oracle (algorithm public, 16-bit seed secret) and a
# visible seed file for local exploration. The verifier re-seeds the daemon
# through an ephemeral keyfile for every case, so the deliverable must recover
# the live key from oracle queries.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN chmod 644 /app/cipher_service.py /app/.cipher_seed
