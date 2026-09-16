# bracket-cinder: gallery-dl keyword-value format strings crash with
# "TypeError: sequence item N: expected str instance, X found" when literal
# text is combined with {placeholders} that resolve to non-text values.
#
# The image clones mikf/gallery-dl SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone
# the agent works on; the extraction uses a throwaway bare clone that is
# deleted. Pure Python, no submodules, no C build, no optional deps.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=f77c330d83018b25924d219f96aaf4f064bd3eaf
ARG FIX_SHA=098fbba8d7eef0e164b1dadbbf459002c68347e8

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves. The fix
# commit is never fetched into this clone, and `git cat-file -e` proves it is
# not reachable.
RUN git clone --depth 1 https://github.com/mikf/gallery-dl.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin f77c330d83018b25924d219f96aaf4f064bd3eaf \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/mikf/gallery-dl.git \
 && git fetch --depth 1 origin 098fbba8d7eef0e164b1dadbbf459002c68347e8 \
 && mkdir -p /opt/golden \
 && git show 098fbba8d7eef0e164b1dadbbf459002c68347e8:test/test_formatter.py \
      > /opt/golden/test_formatter.py \
 && test -s /opt/golden/test_formatter.py \
 && grep -q "test_fmt_func_multi" /opt/golden/test_formatter.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm every cache at build time; trial is offline ----------------------
# No project install is needed (the project's tests add the repo root to
# sys.path); only the test runner is extra. pytest is pinned.
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN pip install --no-cache-dir pytest==9.1.1

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]