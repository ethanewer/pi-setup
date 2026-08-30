FROM bench-base:ubuntu-24.04

WORKDIR /app

# LLVM / clang toolchain (LLVM 18), z3 SMT solver plus Python bindings.
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang \
        llvm-18 \
        llvm-18-tools \
        z3 \
        python3 \
        python3-z3 \
    && rm -rf /var/lib/apt/lists/*

# Bake the shipped inputs: loose per-module IR + the sample ELF (no-pie so the
# section addresses are real), keeping the C source available for the agent to
# rebuild with debug metadata.
COPY files/ /app/
RUN clang -c -emit-llvm /app/src/module_a.c -o /app/module_a.ll \
 && clang -c -emit-llvm /app/src/module_b.c -o /app/module_b.ll \
 && clang -no-pie -c /app/src/module_a.c -o /tmp/module_a.o \
 && clang -no-pie -c /app/src/module_b.c -o /tmp/module_b.o \
 && clang -no-pie -c /app/src/sample.c -o /tmp/sample.o \
 && clang -no-pie /tmp/module_a.o /tmp/module_b.o /tmp/sample.o -o /app/sample.elf \
 && chmod -R a+rX /app

WORKDIR /app