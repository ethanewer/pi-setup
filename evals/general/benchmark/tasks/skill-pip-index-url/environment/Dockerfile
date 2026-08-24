FROM bench-base:python-3.12

WORKDIR /app

# Prebuilt wheel and the PEP 503 simple index page (the "repo" to serve).
# Layout: /app/index.html is the root simple index; /app/myprobe/ is the
# project page holding the wheel.
RUN mkdir -p /app/myprobe
COPY files/whl/myprobe-0.1.0-py3-none-any.whl /app/myprobe/
COPY files/index.html /app/index.html
COPY files/index.html /app/myprobe/index.html