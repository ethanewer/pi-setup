FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Ensure the exports directory exists (the deliverable file is produced by the
# agent's/oracle's run of the exporter).
RUN mkdir -p /app/exports
