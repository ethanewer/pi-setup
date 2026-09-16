# ingot-flood: modernise the 1997 id-Software linuxdoom-1.10 source so it
# builds and runs on a 2024 toolchain (gcc 13, glibc 2.39, X11, headless).
#
# The tree is shipped PRISTINE and deliberately BROKEN for the modern
# toolchain: the whole point of the task is that the agent repairs the
# upstream source and proves it by building it and playing a demo. We
# therefore do NOT build at image-build time. We DO install the exact
# compile/run prerequisites (including Xvfb for the headless X11 run) and
# bake an authored test fixture (minimal IWAD + recorded demo) into the
# image so the trial is network-free.
#
# Upstream: https://github.com/id-Software/DOOM (linuxdoom-1.10, 1997).
# This repository is NOT among the frozen Terminal-Bench 2.1 reference
# sources (checked against specs/tb21_source_repositories.json).
FROM bench-base:ubuntu-24.04

# Toolchain + X11 dev headers for building + Xvfb for running the X11
# binary headlessly. Everything here is baked in; nothing is fetched at
# trial time.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      gcc make libc6-dev libx11-dev libxext-dev xvfb \
 && rm -rf /var/lib/apt/lists/*

# git safe-directory: the clone is root-owned and trials may run as uid 1000.
ARG UPSTREAM_SHA=a77dfb96cb91780ca334d0d4cfd86957558007e0
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Shallow, pinned clone; fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/id-Software/DOOM.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Authored harness: the minimal-IWAD/demo generator, the run helper, and a
# pre-generated 100-tic demo fixture. None of this is upstream bytes.
COPY files/ /app/
RUN chmod +x /app/genwad.py /app/run_demo.sh \
 && mkdir -p /app/fixtures \
 && /app/genwad.py /app/fixtures 100 d1 \
 && printf 'DEMO=d1\nTICS=100\n' > /app/fixtures/params.env

# The trial may run as uid 1000; the agent must be able to edit /app/src.
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]