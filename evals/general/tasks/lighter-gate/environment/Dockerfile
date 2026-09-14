FROM bench-base:python-3.12

# ---------------------------------------------------------------------------
# lighter-gate: real-upstream debugging task against pallets/click.
# The agent gets the real repo at PARENT 4271fe28 (shallow, detached), the
# commit immediately before the help-exit-status fix d8763b93 (#1489), so the
# bug is present in the shipped tree. The Dockerfile builds in a read-only
# pristine snapshot of the parent tree (for the verifier's pre-fix direction)
# and extracts the golden tests from the FIX commit through a SEPARATE
# throwaway clone under /tmp that is deleted before the image is finished, so
# the fix objects never enter the repository the agent receives.
# ---------------------------------------------------------------------------
ARG UPSTREAM_SHA=4271fe283dc9365563aebb369ada8d20eee015a8
ARG FIX_SHA=d8763b93021c416549b5f8b4b5497234619410db

# 1. The working clone, pinned fail-closed to the measured parent commit.
#    `git init` + a single depth-1 fetch of the PINNED SHA keeps ONLY the
#    parent commit in the object store: no origin refs are created and the
#    current main tip (whose tree contains the fixed code for this issue) is
#    never fetched. A plain `git clone --depth 1` would fetch the main tip
#    and make the fix readable via `git diff HEAD main`.
RUN mkdir -p /app/src \
 && cd /app/src \
 && git init -q \
 && git remote add origin https://github.com/pallets/click.git \
 && git fetch --depth 1 origin $UPSTREAM_SHA \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && echo "parent-pin-ok"

# 2. Pristine pre-fix snapshot (verifier reference; no .git) and the golden
#    tests extracted from the fix commit via a throwaway /tmp clone that is
#    removed here. Both are left root-owned and not writable by the agent.
RUN mkdir -p /opt/pristine /opt/golden \
 && cd /app/src \
 && git archive HEAD | tar -x -C /opt/pristine \
 && test -f /opt/pristine/src/click/core.py \
 && git clone --depth 1 https://github.com/pallets/click.git /tmp/goldfetch \
 && cd /tmp/goldfetch \
 && git fetch --depth 1 origin $FIX_SHA \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$FIX_SHA" \
 && cp tests/test_commands.py /opt/golden/test_commands.py \
 && cp tests/conftest.py /opt/golden/conftest.py \
 && cd / \
 && rm -rf /tmp/goldfetch \
 && cd /app/src \
 && ! git cat-file -e $FIX_SHA^{commit} \
 && echo "fix-unreachable-in-shipped-clone-ok"

# 3. Project + test dependencies, pinned. click has no runtime deps; the
#    build backend is flit_core and the only test dependency is pytest.
RUN pip install --no-cache-dir pytest==9.1.1 flit_core==3.12.0 \
 && pip install --no-cache-dir -e /app/src

# 4. The trial runs as uid 1000 and must edit the tree and write under /app.
#    /opt/pristine and /opt/golden deliberately stay root-owned 0755.
RUN chmod -R a+rwX /app /app/src \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app
COPY files/ /app/