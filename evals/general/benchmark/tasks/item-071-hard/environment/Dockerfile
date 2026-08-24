FROM bench-base:python-3.12

# CPU-only PyTorch from PyPI (default index ships CPU wheels).
RUN pip install --no-cache-dir torch numpy \
 && rm -rf /root/.cache/pip

WORKDIR /app
COPY files/ /app/
RUN mkdir -p /app/data /app/engine/out \
 && python3 /app/gen_data.py \
 && rm -f /app/gen_data.py