# oakum-landfall: upstream-clone bugfix task on pypa/setuptools.
# The image clones the REAL upstream repository at the PARENT commit (bug
# present), extracts the project's own regression tests from the FIX commit
# into the tree through a throwaway clone (which is deleted again, so the fix
# object never enters the shipped repository), installs the package in
# editable mode with the pinned test dependencies, and bakes a pristine
# pre-fix snapshot the verifier uses for the failing direction.

FROM bench-base:python-3.12

ARG UPSTREAM_SHA=d8da7dfaa0cef4a69ee21d9406391651c4dc5ce4
ARG FIX_SHA=9559193e1eb12aee0a9eb6cc754e519e6e09ecb4

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONNOUSERSITE=1

# Build/test toolchain. gcc is needed by a project test fixture that compiles
# a tiny C extension; libc6-dev provides C stdlib headers (stdlib.h), which
# the base image does not ship.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && (useradd -m -u 1000 -s /bin/bash agent || true)

# 1) Working tree: shallow clone of the real upstream repository pinned to
#    the PARENT commit. `git init` + one depth-1 fetch of the pinned SHA, so
#    the object store in /app/src holds exactly that one commit and nothing
#    else; the fix commit is NEVER fetched here and is asserted unreachable
#    (the build fails closed if that ever stops being true).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pypa/setuptools.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q -f FETCH_HEAD \
 && git switch -q --detach \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test -z "$(git status --porcelain)" \
 && chmod -R a+rwX /app/src \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# 2) Golden regression tests: extracted through a SEPARATE throwaway clone at
#    the FIX commit, copied into the working tree, then the throwaway clone
#    is deleted, so the fix object never enters the shipped repository. The
#    two files are sha256-pinned at build time into /opt/pins so the verifier
#    can detect any tampering with byte-for-byte certainty.
RUN git init -q /tmp/golden \
 && cd /tmp/golden \
 && git remote add origin https://github.com/pypa/setuptools.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && git checkout -q -f FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${FIX_SHA}" \
 && cp setuptools/tests/test_bdist_wheel.py setuptools/tests/test_dist_info.py /app/src/setuptools/tests/ \
 && cd /tmp \
 && rm -rf /tmp/golden \
 && cd /app/src \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && grep -q 'unicode_dist-0.1.dist-info' setuptools/tests/test_bdist_wheel.py \
 && mkdir -p /opt/pins \
 && sha256sum setuptools/tests/test_bdist_wheel.py > /opt/pins/golden-bdist.sha256 \
 && sha256sum setuptools/tests/test_dist_info.py > /opt/pins/golden-distinfo.sha256 \
 && echo "golden tests extracted and pinned"

# 3) Editable install of the pinned tree using the project's [test] extra,
#    then explicit pins. wheel==0.44.0 is REQUIRED: wheel>=0.45 emits a
#    DeprecationWarning at import that the repository's 'error' warning
#    filter turns into a pytest collection error.
RUN cd /app/src \
 && pip install --no-cache-dir -e '.[test]' \
 && pip install --no-cache-dir 'pytest==8.4.2' 'wheel==0.44.0' \
 && python3 -c "import setuptools; assert '/app/src' in setuptools.__file__, setuptools.__file__"

# 4) Pristine PRE-FIX snapshot of the complete tree (bug intact), used by the
#    verifier to run the agent's reproduction against the pre-fix tree.
RUN tar czf /opt/pristine.tar.gz -C /app src \
 && ls -la /opt/pristine.tar.gz

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]