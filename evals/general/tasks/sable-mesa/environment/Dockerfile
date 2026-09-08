FROM bench-base:python-3.12

# Provide the PEP 517 build toolchain needed to install the package offline.
RUN python3 -m pip install --no-cache-dir --upgrade setuptools==84.0.0 wheel==0.48.0

WORKDIR /app

COPY files/ /app/
