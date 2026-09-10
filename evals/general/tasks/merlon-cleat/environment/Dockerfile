# merlon-cleat — Pennant framing crate fixture image.
# Rust toolchain from the Ubuntu archive (rustc/cargo 1.75), plus gcc for the
# allocation-counting shim and git for the fixture repository's build-time
# history. The crate itself is dependency-free: graders build it offline.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        rustc cargo gcc git \
    && rm -rf /var/lib/apt/lists/*

# The fixture repository below is created by gen_fixture.sh during this
# build, so it is root-owned; record the exception system-wide so git works
# for whatever user a harness picks later. Also set a committer identity for
# the build-time commits.
RUN git config --system --add safe.directory '*' && \
    git config --system user.email "build@localhost" && \
    git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

RUN bash /app/toolchain/gen_fixture.sh && rm -rf /app/toolchain

CMD ["/bin/bash"]