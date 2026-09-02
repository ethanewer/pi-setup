FROM bench-base:python-3.12

# Provide the PEP 517 build toolchain needed to install the package offline.
RUN python3 -m pip install --no-cache-dir --upgrade setuptools wheel

WORKDIR /app

COPY files/ /app/
