FROM bench-base:python-3.12

WORKDIR /app

# CPU-only PyTorch wheels (torch.distributed with the gloo backend)
RUN pip install --no-cache-dir torch>=2.2

COPY files/values.txt /app/values.txt