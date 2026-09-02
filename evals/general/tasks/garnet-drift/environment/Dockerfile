FROM bench-base:python-3.12

# openssl CLI is needed by the deliverable tool and the verifier.
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# PKI fixtures: the edge service key/cert pair, a retired decoy pair, and the
# original CSR. These are static files committed with the task.
COPY files/ /app/
