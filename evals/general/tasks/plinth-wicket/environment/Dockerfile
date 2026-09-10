# plinth-wicket — DOMPurify XSS sanitizer hardening task
#
# Clones the real cure53/DOMPurify upstream at the frozen 3.4.15 release and
# warms its node_modules at build time so the trial runs fully offline. The
# agent hardens an app-level sanitizer built on this clone's DOMPurify build.
FROM bench-base:node-22

# The clone below is created by this RUN, so it is root-owned; record the git
# safe.directory exception system-wide (per /etc/gitconfig) so the trial works
# whichever uid the harness runs it as, and set a build committer identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Frozen upstream revision: tag 3.4.15 (annotated tag ab29c970... peels to this
# commit). Asserted so a force-moved tag fails the build closed instead of
# silently swapping the project under the measured task.
WORKDIR /app/src
ARG UPSTREAM_SHA=1d7460c4f8a27be825c11b1c9d346d79db32c1e5
RUN git clone --depth 1 --branch 3.4.15 https://github.com/cure53/DOMPurify.git /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && echo "PIN OK: $(git rev-parse HEAD)"

# Warm every dependency at build time so the trial (network_mode: none) runs
# the project's own jsdom suite and the agent's node scripts with no fetches.
RUN npm ci --no-audit --no-fund

WORKDIR /app
COPY files/ /app/
