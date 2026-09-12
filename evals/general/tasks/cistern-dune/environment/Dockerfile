# cistern-dune: click FuncParamType swallows the ValueError message.
#
# The image clones pallets/click SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone the
# agent works on; the extraction uses a throwaway bare clone that is deleted.
#
# Pure-Python project: pip install -e . (flit_core backend) is fast. Only
# pytest is needed to run the project's own test suite.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=5b9630f50fde938b72ad8c99542efe3a6f5717e2
ARG FIX_SHA=fc6c7c47edd6110b6bd5a1a5297b2035214b0cd1

RUN apt-get update && apt-get install -y --no-install-recommends less \
 && rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/pallets/click.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 5b9630f50fde938b72ad8c99542efe3a6f5717e2 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pallets/click.git \
 && git fetch --depth 1 origin fc6c7c47edd6110b6bd5a1a5297b2035214b0cd1 \
 && mkdir -p /opt/golden \
 && git show fc6c7c47edd6110b6bd5a1a5297b2035214b0cd1:tests/test_types.py \
      > /opt/golden/test_types.py \
 && test -s /opt/golden/test_types.py \
 && grep -q "test_func_param_type_uses_value_error_message" /opt/golden/test_types.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod -R a+rX /opt/golden

# ---- install (warm every cache at build time; trial is offline) ------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# pytest is pinned to the version click's own uv.lock resolves (9.0.2);
# newer pytest 9.1 turns one of click's parametrized iterables into a
# PytestRemovedIn10Warning that its filterwarnings=error config rejects.
RUN cd /app/src \
 && pip install -e . \
 && pip install pytest==9.0.2

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]