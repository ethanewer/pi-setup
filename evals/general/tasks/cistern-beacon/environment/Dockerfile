# cistern-beacon: sympy's linprog crashes on the unconstrained problem.
#
# The image creates a git checkout of sympy/sympy whose object store holds
# exactly ONE commit: the PARENT commit 6a968f72 (the real upstream bug is
# present in the working tree). The project's own regression test for the bug
# is extracted from the FIX commit at build time into /opt/golden/ (upstream
# bytes never enter this repository). The fix commit is never fetched into the
# working clone, so the answer is not reachable from the tree the agent works
# on; the extraction uses a throwaway bare clone that is deleted afterwards.
#
# Pure-Python project: sympy's only runtime dependency is mpmath, which
# `pip install -e .` pulls in at image build time (warm cache, trial is
# offline). pytest and hypothesis are the editorially minimal test
# dependencies the project's own conftest.py requires.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=6a968f7201e5d9187b50dbdc2cc66b17594a59ac
ARG FIX_SHA=66ee6e06934fede513c7504413baacbf80917186

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working checkout: buggy parent commit, fix commit unreachable ----------
# Fetch exactly the parent commit (shallow). GitHub permits fetching an
# arbitrary reachable commit SHA, so the working clone's object store ends up
# containing exactly one commit; the fix commit is not in it and cannot become
# reachable without network. Fail closed if the pin ever moves.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 origin 6a968f7201e5d9187b50dbdc2cc66b17594a59ac \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare -q /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/sympy/sympy.git \
 && git fetch --depth 1 -q origin 66ee6e06934fede513c7504413baacbf80917186 \
 && mkdir -p /opt/golden \
 && git show 66ee6e06934fede513c7504413baacbf80917186:sympy/solvers/tests/test_simplex.py \
      > /opt/golden/test_simplex.py \
 && test -s /opt/golden/test_simplex.py \
 && grep -q "def test_29368" /opt/golden/test_simplex.py \
 && grep -q "linprog(\[1\]) == (0, \[0\])" /opt/golden/test_simplex.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; the trial is offline) ---------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN cd /app/src \
 && pip install -e . \
 && pip install pytest==9.1.1 hypothesis==6.168.0

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]