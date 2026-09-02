FROM bench-base:python-3.12

WORKDIR /app

# The platform preinstalls the pinned ML toolchain. These versions are the
# immutable baseline: provisioning must NEVER upgrade, downgrade, or remove
# them (offline_load.py depends on them).
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    transformers==5.16.1

# Chain-query helper source (installed into a venv by provision.sh) and the
# offline load-path consumer that pins the ML toolchain.
COPY files/ /app/
