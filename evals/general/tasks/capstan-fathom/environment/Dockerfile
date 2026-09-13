# capstan-fathom: flake8 raises `AttributeError: 'int' object has no
# attribute 'rstrip'` -- instead of emitting its syntax-error report -- when
# it checks any Python file that fails to parse, on Python 3.10 and newer
# (real upstream issue PyCQA/flake8#1372).
#
# The image clones PyCQA/flake8 and checks out upstream PARENT commit
# d25cc10e382bcbd59cea47e0172f1e35cd3ee90d (the commit immediately before
# 85c2be3b5291a73a2e737219c040019c14cf3eee fixed #1372), so the agent gets the
# real repository with the real bug still in it. The instruction names neither
# the issue nor the commit nor the file to change.
#
# The fix commit is never made reachable from /app/src. The working clone is
# created with `git init` plus a single shallow `git fetch` of the parent SHA,
# so its object store holds exactly one commit (asserted below). The project's
# own regression test (tests/integration/test_checker.py, which the fix commit
# introduced) is extracted through a throwaway bare clone that is deleted
# immediately afterwards, so those upstream bytes land only in /opt/golden and
# in the working-tree copy the same way the mining reproduction overlaid them
# (`git checkout <fix-sha> -- tests/integration/test_checker.py`) -- never in
# this task's tree, and never as a commit object reachable from /app/src.
#
# The last build step re-runs the regression test and requires the mined
# failure (the AttributeError above) so the image demonstrably ships the bug.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=d25cc10e382bcbd59cea47e0172f1e35cd3ee90d
ARG FIX_SHA=85c2be3b5291a73a2e737219c040019c14cf3eee

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Runtime toolchain, pinned to the version era of the checkout (flake8 3.9.2).
RUN pip install --no-cache-dir -q \
      pyflakes==2.3.1 \
      pycodestyle==2.7.0 \
      mccabe==0.6.1 \
      pytest==6.2.5

# ---- working clone: buggy parent commit only, fix commit unreachable -----
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/PyCQA/flake8.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git -C /app/src rev-list --count HEAD)" = "1" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the fix commit -------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/PyCQA/flake8.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:tests/integration/test_checker.py \
      > /opt/golden/test_checker.py \
 && test "$(sha256sum /opt/golden/test_checker.py | cut -d' ' -f1)" \
      = "cbace8aece29be37ebc68b91ff46ded4ae9f0583ac0b7c7b9d90130b2771d844" \
 && grep -q "test_handling_syntaxerrors_across_pythons" /opt/golden/test_checker.py \
 && rm -rf /tmp/fixsrc

# ---- overlay the golden regression test into the working tree -------------
# (mirrors the mining reproduction: `git checkout <fix> -- tests/integration/...`)
RUN cp /opt/golden/test_checker.py /app/src/tests/integration/test_checker.py \
 && cmp -s /opt/golden/test_checker.py /app/src/tests/integration/test_checker.py

# pytest and imported modules would otherwise dirty the working-tree status;
# the verifier's provenance check must be able to see exactly the fix.
RUN printf '__pycache__/\n*.py[cod]\n.pytest_cache/\n' \
      >> /app/src/.git/info/exclude

# ---- the image must ship the mined failing state ---------------------------
# The regression test must fail with the AttributeError inside this image,
# otherwise the task's oracle cannot pass.
RUN cd /app/src \
 && (PYTHONPATH=/app/src/src python3 -m pytest \
      tests/integration/test_checker.py \
      -k test_handling_syntaxerrors_across_pythons \
      -q -W ignore::DeprecationWarning -p no:cacheprovider \
      || true) > /tmp/repro.out 2>&1 \
 && grep -q "AttributeError: 'int' object has no attribute 'rstrip'" /tmp/repro.out

WORKDIR /app

# The trial may run as uid 1000 and must be able to edit the checkout.
RUN chmod -R a+rwX /app/src

CMD ["/bin/bash"]