FROM bench-base:python-3.12

WORKDIR /app

# Provide the PEP 517 build toolchain the offline-install check needs.
RUN python3 -m pip install --no-cache-dir --upgrade setuptools wheel

COPY files/ /app/
