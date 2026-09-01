FROM bench-base:python-3.12

WORKDIR /app

# CPU-only classifier work: torch, numpy, safetensors. All install from PyPI
# through the corporate CA proxy baked into bench-base.
RUN pip install --no-cache-dir --quiet \
        torch==2.4.1 \
        numpy \
        safetensors

COPY files/ /app/
