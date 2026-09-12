# bracket-cleat: click refuses a valueless flag declared with flag_value + default.
#
# The image clones pallets/click SHALLOW at the PARENT commit (the real
# upstream bug, issue #3084, is present in the working tree) and extracts the
# project's own regression tests for the bug from the FIX commit at build
# time into /opt/golden/ (upstream bytes never enter this repository). The
# fix commit is a descendant of the parent, but it is never fetched into the
# working clone, so it is unreachable from /app/src; the golden extraction
# uses a throwaway bare clone that is deleted afterwards.
#
# Pure-Python project (flit backend): `pip install -e .` is fast and the
# imported code is exactly the checked-out (buggy) tree.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=7f7bbe4569ea68e8dabee232eade069ef3310aea
ARG FIX_SHA=91de59c6c8abc8251e7af551cd4546cc964288af

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/pallets/click.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 7f7bbe4569ea68e8dabee232eade069ef3310aea \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression tests from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pallets/click.git \
 && git fetch --depth 1 origin 91de59c6c8abc8251e7af551cd4546cc964288af \
 && mkdir -p /opt/golden \
 && git show 91de59c6c8abc8251e7af551cd4546cc964288af:tests/test_options.py \
      > /opt/golden/test_options.py \
 && test -s /opt/golden/test_options.py \
 && grep -q "test_flag_value_optional_behavior" /opt/golden/test_options.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; the trial must not need the
#      network even though this host may have egress) ------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX=/tmp/pycache

RUN cd /app/src \
 && pip install -e . \
 && pip install --no-cache-dir pytest==8.4.2

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]