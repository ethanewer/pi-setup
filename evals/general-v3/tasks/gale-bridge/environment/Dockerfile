FROM bench-base:python-3.12
WORKDIR /app

# Tooling for the Gale spectral-analysis dev harness: Jupyter notebook authoring,
# headless Vim for the plugin check, gawk for ranked top-k, jq for record transforms.
RUN pip install --no-cache-dir nbformat nbclient ipykernel matplotlib && \
    apt-get update && \
    apt-get install -y --no-install-recommends vim gawk jq && \
    rm -rf /var/lib/apt/lists/*