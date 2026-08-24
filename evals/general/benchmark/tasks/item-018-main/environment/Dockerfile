FROM bench-base:ubuntu-24.04

WORKDIR /app

# C++ toolchain + debugger for the pool allocator task.
RUN apt-get update && apt-get install -y --no-install-recommends g++ libc6-dev make gdb valgrind \
    && rm -rf /var/lib/apt/lists/*

COPY files/cashier /app/cashier