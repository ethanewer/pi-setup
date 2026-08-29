FROM bench-base:ubuntu-24.04
ENV DEBIAN_FRONTEND=noninteractive

# Instruct/ for the dune-mantle formal-verification suite: system LLVM (clang/opt),
# the z3 satisfiability solver (+ python bindings), and the Coq compiler. All CPU, one container.
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang-18 \
        llvm-18 \
        z3 \
        python3 \
        python3-z3 \
        coq \
        time \
    && rm -rf /var/lib/apt/lists/*

# Strip-pinned LLVM-18 toolchain under bare, globally-invocable names so the
# symbolic engine can be presented as a single on-PATH binary.
RUN set -eu; \
    for t in clang-18 clang++-18 opt-18 llvm-as-18 llvm-dis-18 llvm-config-18 llvm-link-18 lli-18; do \
        ln -sf /usr/bin/${t} /usr/bin/${t%-18}; \
    done

WORKDIR /app
COPY files/ /app/