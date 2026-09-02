# hollow-dial - revive old machines at the binary level. environment.
# Base image plus a C toolchain (to compile the agent's MIPS interpreter and the
# verifier's independent recompile) and a Python runtime (for classify.py and the
# Liz evaluator). The scenario fixtures (PDP-11 a.out, MIPS ELF, Liz sources) are
# generated into /app/samples at build time by tools/gen_fixtures.py.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gcc libc6-dev binutils python3 && \
    rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# Generate the in-image sample corpus (never tests/ or solution/).
RUN python3 /app/tools/gen_fixtures.py --app /app/samples && rm -rf /app/tools/__pycache__

WORKDIR /app
