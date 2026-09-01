FROM bench-base:python-3.12

WORKDIR /app

# CPU training stack for the snapshot task (deterministic pinned install).
RUN pip install --no-cache-dir --disable-pip-version-check \
    numpy==2.5.2 \
 && pip install --no-cache-dir --disable-pip-version-check torch==2.13.0

# Provided fixtures: visible run data + config. No solver code is shipped.
COPY files/ /app/

