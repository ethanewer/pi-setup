FROM bench-base:node-22

# fluxline is a git repository when the trial starts; it is built inside this
# image, runs as a user git may not recognize, and is safe for any user.
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

# ---------------------------------------------------------------------------
# Build the fixture repository with its incremental git history, then run the
# project's own test suite so the image ships green (the suite is small-data
# and does not exercise the working-set budget; the shipped HEAD is the
# regression this task is about).
# ---------------------------------------------------------------------------
RUN bash /app/build_repo_git.sh \
    && rm /app/build_repo_git.sh \
    && cd /app/fluxline && node --test > /tmp/fluxline-test.log 2>&1 \
    && tail -8 /tmp/fluxline-test.log