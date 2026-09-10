FROM bench-base:python-3.12

# The fixtures below are git repositories created at build time (root-owned);
# record a system-wide safe.directory exception plus a committer identity so
# git works for whichever user the trial runs as.
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "Buildbot"

WORKDIR /app

COPY files/ /app/

# Generate the three scenario repositories (deterministic: pinned identities
# and timestamps, so the same commit ids as the pre-state bundles shipped
# under tests/hidden).
RUN python3 /app/make_fixtures.py /app && rm -f /app/make_fixtures.py