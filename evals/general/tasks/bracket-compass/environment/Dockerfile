# bracket-compass: jinja2 required-block statement crash.
#
# The image clones pallets/jinja SHALLOW at the PARENT commit 37f5b058… (the
# real upstream bug is present in the working tree) and installs it in editable
# mode, so the code the agent imports is exactly the checked-out Python source
# and its edits take effect immediately. The project's own regression test for
# the bug is extracted from the FIX commit at build time into /opt/golden/
# (upstream bytes never enter this repository). The fix commit is a descendant
# of the parent, so it is NOT reachable from the depth-1 working clone; the
# extraction uses a throwaway bare clone that is deleted afterwards.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=37f5b058ee4aaa01994ae4d378fc015bde484933
ARG FIX_SHA=051df10c7b95b735ee53eeb1e9c8de1eb48ead14

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of the default branch cannot contain the parent SHA, so fetch
# the parent by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/pallets/jinja.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 37f5b058ee4aaa01994ae4d378fc015bde484933 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pallets/jinja.git \
 && git fetch --depth 1 origin 051df10c7b95b735ee53eeb1e9c8de1eb48ead14 \
 && mkdir -p /opt/golden \
 && git show 051df10c7b95b735ee53eeb1e9c8de1eb48ead14:tests/test_inheritance.py \
      > /opt/golden/test_inheritance.py \
 && test -s /opt/golden/test_inheritance.py \
 && grep -q "def test_invalid_required" /opt/golden/test_inheritance.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN cd /app/src \
 && python3 -m pip install -e . \
 && python3 -m pip install pytest==7.4.3 pytest-timeout==2.4.0 \
            trio==0.34.0 MarkupSafe==3.0.3

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]