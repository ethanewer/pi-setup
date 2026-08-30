# Task Dockerfile for slate-anchor.
#
# Base: python-3.12 + the C toolchain and binutils/file the verifier needs
# for linkage checks. The legacy plotsmith tree ships WITH its X11 frontend
# enabled by default (./configure defaults to --with-x); there is no real
# X11 stack, no display, and no network at run/verify time.
FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential binutils file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fixtures shipped in the image (do not modify):
#   /app/plotsmith/      - legacy source tree (configure/Makefile/core/gui/compat)
#   /app/jobs/visible-job.txt - the visible plotting job
COPY files/ /app/

RUN chmod +x /app/plotsmith/configure

CMD ["/bin/bash"]
