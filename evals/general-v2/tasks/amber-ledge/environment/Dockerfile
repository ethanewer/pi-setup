FROM bench-base:node-22

# python3 runtime (the task deliverables span Node.js and Python).
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/

CMD ["bash"]