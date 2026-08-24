FROM bench-base:python-3.12

WORKDIR /app

# Prebuilt wheel and the PEP 503 simple index page (the "repo" to serve).
RUN mkdir -p /app/repo/myprobe
COPY files/whl/myprobe-0.1.0-py3-none-any.whl /app/repo/myprobe/
COPY files/index.html /app/index.html