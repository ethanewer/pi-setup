# cistern-gate: pip requirement lines with invalid markers must not crash
# with an internal InvalidMarker traceback.
#
# The image clones pypa/pip SHALLOW at the PARENT commit (the real upstream
# bug is present in the working tree) and extracts the project's own regression
# test for the bug from the FIX commit at build time into /opt/golden/
# (upstream bytes never enter this repository). The fix commit is extracted via
# a THROWAWAY bare clone that is deleted, so the fix commit is NOT reachable
# from the depth-1 clone the agent works on.
#
# pip installs itself in editable mode from the tree (PEP 660, flit-core
# backend, --no-build-isolation), so `import pip` anywhere in the container
# resolves to /app/src/src/pip and the bug reproduces plainly with the system
# python. Pure-Python; no C extensions.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=9d0e2601f8c82765b0fe92001540e9a7ddd4fdf1
ARG FIX_SHA=95ef105f4eea913c09170dab3f4b6efebddf2843

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# Clone the default branch shallow (a few MB for pip), then fetch the parent
# commit by SHA, detach onto it and fail closed if upstream ever moves.
# --depth 1 means no ancestor objects are present, so the fix commit (made
# after the parent on the same line of history) is not among them.
RUN git clone --depth 1 https://github.com/pypa/pip.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 9d0e2601f8c82765b0fe92001540e9a7ddd4fdf1 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pypa/pip.git \
 && git fetch --depth 1 origin 95ef105f4eea913c09170dab3f4b6efebddf2843 \
 && mkdir -p /opt/golden \
 && git show 95ef105f4eea913c09170dab3f4b6efebddf2843:tests/unit/test_req.py \
      > /opt/golden/test_req.py \
 && test -s /opt/golden/test_req.py \
 && grep -q "def test_markers_invalid" /opt/golden/test_req.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Test dependencies needed by the tree's own unit-test machinery
# (tests/conftest.py imports installer and werkzeug; tests.lib imports
# scripttest and virtualenv; the build backend is flit-core).
RUN pip install flit-core==3.12.0 \
 && pip install pytest==9.1.1 scripttest==3.0 virtualenv==21.7.9 \
            installer==1.0.1 werkzeug==3.1.8 setuptools==79.0.1 \
 && cd /app/src \
 && pip install -e . --no-build-isolation

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app \
 && chmod a+r /opt/golden/test_req.py

CMD ["/bin/bash"]