FROM bench-base:python-3.12

WORKDIR /app

# Provide the PEP 517 build toolchain the task needs to build a wheel offline.
RUN python3 -m pip install --no-cache-dir --upgrade setuptools wheel

COPY files/ /app/