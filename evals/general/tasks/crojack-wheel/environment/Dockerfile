# crojack-wheel: real-upstream debugging task on sqlalchemy/sqlalchemy.
#
# The image ships the upstream tree at the PARENT commit (the commit just
# before the upstream fix for issue #13176). The FIX commit object is never
# fetched into /app/src: the working repo is a depth-1 fetch cut at the
# parent SHA, so `git log --all` / `git cat-file -e <FIX>` cannot reach it.
# The golden regression test is extracted from the FIX commit through a
# SEPARATE throwaway clone under /tmp which is rm -rf'd afterwards, and is
# stored as /opt/golden/test_session.py for the verifier only.
ARG PARENT_SHA=a49a4f021ad9c9ff69f5482881b00f831d523a22
ARG FIX_SHA=d466d375889ee266ef928b6fbb6d673bda6beeb1
ARG UPSTREAM_URL=https://github.com/sqlalchemy/sqlalchemy.git

FROM bench-base:python-3.12

ARG PARENT_SHA
ARG FIX_SHA
ARG UPSTREAM_URL

WORKDIR /app

# --- working tree pinned to the PARENT commit --------------------------------
# Shallow fetch of the parent SHA only; the commit graph is cut at the parent
# so the fix is not even in the object store. The build fails closed if
# upstream moved the SHA or if the fix object is somehow already present.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin ${UPSTREAM_URL} \
 && git fetch --depth 1 origin ${PARENT_SHA} \
 && git checkout -q ${PARENT_SHA} \
 && test "$(git rev-parse HEAD)" = "${PARENT_SHA}" \
 && if git cat-file -e "${FIX_SHA}^{commit}"; then \
      echo "FIX COMMIT PRESENT IN WORKING CLONE - FAILING THE BUILD" >&2; \
      exit 1; \
    fi \
 && git config --system --add safe.directory '*' \
 && git config --system user.email build@localhost \
 && git config --system user.name build

# --- golden regression test, pulled from the FIX commit, never in /app/src ---
RUN git init /tmp/goldenfetch \
 && cd /tmp/goldenfetch \
 && git remote add origin ${UPSTREAM_URL} \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git checkout -q ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && cp test/orm/test_session.py /opt/golden/test_session.py \
 && cd / \
 && rm -rf /tmp/goldenfetch \
 && grep -q "test_get_with_for_update_use" /opt/golden/test_session.py \
 && ! grep -q "test_get_with_for_update_use" \
         /app/src/test/orm/test_session.py

# --- pristine PARENT tree for the verifier's pre-fix concept check -----------
# git archive of the parent commit: identical sources to what the agent
# starts with, but no .git, so it can never be confused with the working tree.
RUN mkdir -p /opt/prefix \
 && git -C /app/src archive --format=tar ${PARENT_SHA} | tar -x -C /opt/prefix \
 && test -f /opt/prefix/lib/sqlalchemy/orm/session.py \
 && test ! -e /opt/prefix/.git

# --- dependencies (pins verified in the mining container) -------------------
RUN cd /app/src \
 && pip install --no-cache-dir -e '.[asyncio]' pytest==9.1.1 pytest-xdist==3.8.0 \
 && chmod -R a+rwX /app/src \
 && chmod -R a+rX /opt/prefix /opt/golden /app \
 && touch /etc/concat-lock-proof

RUN echo "crojack-wheel build ok"