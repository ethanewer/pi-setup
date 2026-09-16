# cistern-cairn: express `res.clearCookie` maxAge/expires override bug.
#
# Clones expressjs/express shallow at the PARENT commit (the real upstream bug
# is present in the working tree) and extracts the project's own regression
# test for the bug from the FIX commit at build time into /opt/golden/.
# The fix commit is the direct child of the parent, so it is NOT reachable
# from the depth-1 parent clone; extraction uses a throwaway bare clone that
# is deleted. node_modules is warmed at build time so the trial runs fully
# offline; node_modules and package-lock are gitignored upstream, so they
# survive any `git reset`/`clean` the agent runs.
FROM bench-base:node-22

ARG UPSTREAM_SHA=160b91cbf79b595712b694c3513c347551d17fbe
ARG FIX_SHA=82fc12a40b3e6694e9a2c9b1376e7548d95779f6

# The clones below are created by this build, so they are root-owned; record a
# system-wide safe.directory exception (per /etc/gitconfig) so the trial works
# whichever uid the harness runs it as, and give build-time git an identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves. The fix
# commit is a descendant of the parent, so its object is absent from this
# depth-1 clone; we assert that, and remove the remote so no origin ref (which
# would point at newer master history) survives in the working clone.
RUN git clone --depth 1 https://github.com/expressjs/express.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 160b91cbf79b595712b694c3513c347551d17fbe \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/expressjs/express.git \
 && git fetch --depth 1 origin 82fc12a40b3e6694e9a2c9b1376e7548d95779f6 \
 && mkdir -p /opt/golden \
 && git show 82fc12a40b3e6694e9a2c9b1376e7548d95779f6:test/res.clearCookie.js \
      > /opt/golden/res.clearCookie.js \
 && test -s /opt/golden/res.clearCookie.js \
 && grep -q "should ignore maxAge" /opt/golden/res.clearCookie.js \
 && grep -q "should ignore user supplied expires param" /opt/golden/res.clearCookie.js \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
WORKDIR /app/src
RUN npm install --no-audit --no-fund --no-package-lock --loglevel=error \
 && rm -rf /root/.npm

WORKDIR /app
COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
