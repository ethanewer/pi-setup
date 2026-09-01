FROM bench-base:ubuntu-24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/app/bin:${PATH}"
COPY files/ /app/
WORKDIR /app

# Zephyr Summit toolchain bundle:
#  - gcc/make/binutils: bootstrap + ELF (readelf) for the from-source compiler
#  - coq 8.18: compile Coq source to .vo proof object
#  - scala 2.11 + default-jdk: scalac -> runnable assembly JAR
#  - z3: CLI constraint solver used by the symbolic engine
#  - llvm-16/clang-16: system LLVM toolchain the symbolic engine reports against
#  - python venv with the z3-solver bindings for the symbolic engine
RUN apt-get update -qq && \
    apt-get install -y -qq \
        gcc g++ make binutils \
        coq z3 python3 python3-venv python3-pip \
        default-jdk scala \
        llvm-16 clang-16 \
    && python3 -m venv /opt/z3venv \
    && /opt/z3venv/bin/pip install --quiet --no-cache-dir \
        --index-url https://pypi.org/simple z3-solver \
    && mkdir -p /app/proofs /app/artifact /app/bin \
    && chmod -R a+rX /app

RUN echo "== zephyr-summit sanity ==" && \
    which gcc make readelf coqc scalac z3 clang-16 llvm-config-16 java jar && \
    coqc --version | head -1 && \
    scala -version 2>&1 | head -1 && \
    /opt/z3venv/bin/python -c "import z3; print('z3-solver', z3.get_version_string())"
