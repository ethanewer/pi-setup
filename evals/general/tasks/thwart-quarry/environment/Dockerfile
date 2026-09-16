FROM bench-base:ubuntu-24.04

# redis-server 7.0.15 is the live cache store; the agent's start script
# daemonizes it at trial time (no systemd, no persistence).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends redis-server

# redis-py client library, pinned exactly (PEP 668 marks the system python).
RUN pip install --break-system-packages --no-cache-dir redis==7.0.1

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
WORKDIR /app
COPY files/ /app/