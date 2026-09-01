FROM bench-base:python-3.12
WORKDIR /app
# system utilities used for inspecting the binary evidence artifacts
RUN apt-get update \
    && apt-get install -y --no-install-recommends binutils xxd \
    && rm -rf /var/lib/apt/lists/*
COPY files/ /app/
