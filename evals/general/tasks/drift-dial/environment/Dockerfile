FROM bench-base:node-22

# The task deliverables span Node.js (npm) and Python (HTTP client + verifier).
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# environment fixtures (reference origin + scenario + npm project state)
COPY files/ /app/

CMD ["bash"]