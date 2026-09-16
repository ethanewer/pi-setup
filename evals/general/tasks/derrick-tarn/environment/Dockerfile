# derrick-tarn: upstream-clone extractor task on mikf/gallery-dl, v1.32.11
#
# The upstream repository is shallow-cloned, SHA-pinned and warmed at build
# time (network exists while the image builds). The trial has no network, so
# everything the agent needs is already in this image: the pinned checkout at
# /app/src, the pinned requests dependency, and the loopback mock site for
# the fictional "picdrome" domain whose server lives in /app/mock_site.
#
# The agent's job is to add a new site extractor to the /app/src checkout so
# that the gallery-dl CLI itself downloads picdrome galleries from the mock
# server. /app/src/gallery_dl/extractor/picdrome.py is the deliverable.

FROM bench-base:python-3.12

# refs/tags/v1.32.11 is an annotated tag: `git ls-remote` reports the tag
# object SHA (644e1b5e...), while clones check out the commit it points to
# (2adf2a8e...). The 40-hex commit hash below is the immutable pin; the
# Dockerfile fetches it by hash and fails closed if it ever drifts.
ARG UPSTREAM_SHA=2adf2a8e0041ec55afdcc2211fd5c7ca239a9352

# git-uid-1000 safety and build identity (agents may run as uid 1000).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# The single Python runtime dependency of gallery-dl, pinned. Resolved
# against this base image's own interpreter (Python 3.12).
RUN pip install --no-cache-dir requests==2.32.5

# Clone the upstream project and check out the exact pinned commit: shallow,
# and fetched BY HASH rather than by tag. refs/tags/v1.32.11 is an annotated
# tag, so `git ls-remote` reports the TAG OBJECT's SHA (644e1b5e...) rather
# than the commit it points to; the commit is 2adf2a8e..., and the hash below
# is that immutable commit. Fetching by commit hash removes the tag from the
# trust chain entirely. Fail closed if the hash ever drifts.
RUN git clone --depth 1 https://github.com/mikf/gallery-dl.git /app/src \
    && cd /app/src \
    && git fetch --depth 1 origin $UPSTREAM_SHA \
    && git checkout --detach $UPSTREAM_SHA \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

# Warm the interpreter cache and prove the CLI runs offline exactly as the
# trial will invoke it.
RUN cd /app/src && python3 -m gallery_dl --help >/dev/null \
    && python3 -m gallery_dl --list-extractors | head -5 >/dev/null

WORKDIR /app
# Thread-pool pins (the task is pure Python; these keep any extension libs
# single-threaded as the sweep is one CPU).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=1

COPY files/ /app/