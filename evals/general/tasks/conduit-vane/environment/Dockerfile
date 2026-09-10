FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CARGO_BUILD_JOBS=1

# rustc/cargo 1.75 from the Ubuntu archive; gcc provides the linker rustc
# drives, and git/python3 ship with the base.
RUN apt-get update -qq && \
    apt-get install -y -qq \
        rustc \
        cargo \
        gcc \
        binutils \
        git \
        python3 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The workspace repository is created by the fixture generator below and is
# root-owned; record the exception so every trial user can operate on it.
RUN git config --system --add safe.directory '*'
RUN git config --system user.email "build@localhost" && \
    git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

# Assemble the workspace from templates, build the git history, prove the
# workspace is green (build + tests), and generate the example capture.
RUN python3 /app/gen_workspace.py

RUN rm -rf /app/tpl /app/gen_workspace.py

CMD ["/bin/bash"]
# Acceptance gate re-verification marker (2026-09-09)

# Final acceptance rebuild marker (2026-09-09)
