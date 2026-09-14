# gaff-boom: real upstream bugfix task against explosion/spaCy.
# The image clones the real repository at the pinned PARENT commit (the bug is
# present), extracts the upstream regression test from the FIX commit into
# /opt/golden via a throwaway clone (never fetched into /app/src), warms the
# full pip dependency closure and the Cython extension build, and ships the
# trialled tree read-only-for-root / writable-for-uid-1000 at /app/src.

ARG UPSTREAM_SHA_PARENT=453732d32d55029ea9787ef737c8cf8d626f45b0
ARG UPSTREAM_SHA_FIX=cfa1d3a59abd8ebb859070f97d681120ac9d07a7

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Single-CPU task: keep every numeric thread pool at 1. blis (thinc's BLAS) and
# Cython's parallel build each honour their own env var; the others are the
# standard numpy/OpenMP quartet the suite requires.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    BLIS_NUM_THREADS=1 \
    SPACY_NUM_BUILD_JOBS=1 \
    PYTHONHASHSEED=0

# bench-base:python-3.12 ships no C compiler; spaCy's Cython extensions need
# one both at build time and at trial time (the agent must recompile changed
# extension modules).
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Full pinned dependency closure of spaCy 3.8.11 + test deps, resolved against
# this base image's own interpreter (python 3.12.13) on 2026-09-12. numpy and
# thinc match the mining entry's ranges (>=2,<3 and >=8.3.4,<8.4). Every pin
# is exact; nothing is left to the resolver at image build time or trial time.
RUN python3 -m pip install --no-cache-dir \
    annotated-doc==0.0.5 \
    annotated-types==0.8.0 \
    black==26.5.1 \
    blis==1.3.3 \
    catalogue==2.0.10 \
    certifi==2026.7.22 \
    cfgv==3.5.0 \
    charset-normalizer==3.5.1 \
    click==8.5.0 \
    cloudpathlib==0.25.0 \
    cloudpickle==3.1.2 \
    confection==0.1.5 \
    cymem==2.0.13 \
    Cython==3.3.0 \
    cython-lint==0.21.1 \
    distlib==0.4.3 \
    filelock==3.32.6 \
    flake8==5.0.4 \
    hypothesis==6.168.0 \
    identify==2.6.19 \
    idna==3.19 \
    iniconfig==2.3.0 \
    isort==5.13.2 \
    Jinja2==3.1.6 \
    markdown-it-py==4.2.0 \
    MarkupSafe==3.0.3 \
    mccabe==0.7.0 \
    mdurl==0.1.2 \
    ml_datasets==0.2.1 \
    mock==2.0.0 \
    murmurhash==1.0.15 \
    mypy==1.5.1 \
    mypy_extensions==1.1.0 \
    nodeenv==1.10.0 \
    numpy==2.5.3 \
    packaging==26.3 \
    pathspec==1.1.1 \
    pbr==7.0.3 \
    platformdirs==4.11.8 \
    pluggy==1.6.0 \
    pre_commit==4.6.2 \
    preshed==3.0.13 \
    pycodestyle==2.9.1 \
    pydantic==2.13.5 \
    pydantic_core==2.46.5 \
    pyflakes==2.5.0 \
    Pygments==2.21.0 \
    pytest==9.1.1 \
    pytest-timeout==1.4.2 \
    python-discovery==1.6.0 \
    pytokens==0.4.1 \
    PyYAML==6.0.3 \
    requests==2.34.2 \
    rich==15.0.0 \
    setuptools==84.0.0 \
    shellingham==1.5.4 \
    six==1.17.0 \
    smart_open==7.7.1 \
    sortedcontainers==2.4.0 \
    spacy-legacy==3.0.12 \
    spacy-loggers==1.0.5 \
    srsly==2.5.3 \
    thinc==8.3.11 \
    tokenize_rt==6.2.0 \
    tqdm==4.70.1 \
    typer==0.27.2 \
    typer-slim==0.24.0 \
    types-mock==5.2.0.20260518 \
    types-requests==2.33.0.20260906 \
    types-setuptools==84.0.0.20260812 \
    typing-inspection==0.4.4 \
    typing_extensions==4.16.0 \
    urllib3==2.7.0 \
    virtualenv==21.7.9 \
    wasabi==1.1.3 \
    weasel==0.4.3 \
    wrapt==2.4.1

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which a trial must not be able to look up or fetch) is never fetched
# into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/explosion/spaCy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression test for this bug (the whole
# spacy/tests/vocab_vectors/test_memory_zone.py file exactly as it exists at
# the fix commit, i.e. the parent's three tests plus the new
# test_memory_zone_exception_cleanup) into /opt/golden using a THROWAWAY clone
# that is deleted immediately afterwards, so upstream test bytes never land in
# this task tree and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/explosion/spaCy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:spacy/tests/vocab_vectors/test_memory_zone.py > /opt/golden/test_memory_zone.py \
 && test -s /opt/golden/test_memory_zone.py \
 && grep -q "test_memory_zone_exception_cleanup" /opt/golden/test_memory_zone.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Warm layer: editable install with build isolation disabled (cython, numpy,
# setuptools and every dependency are already present pinned above) compiles
# all Cython extension modules in place and writes spacy.egg-info. The trial
# has no network, so this layer IS the warm cache; an agent or the verifier
# recompiling changed modules afterwards never needs to fetch anything.
RUN cd /app/src \
 && python3 -m pip install --no-cache-dir -e . --no-build-isolation --no-deps -q \
 && python3 -c 'import spacy; assert spacy.__version__ == "3.8.11", spacy.__version__' \
 && test -f spacy/strings.cpython-312-x86_64-linux-gnu.so \
 && test -f spacy/vocab.cpython-312-x86_64-linux-gnu.so \
 && test -z "$(git status --porcelain)" && echo "tree clean after warm install"

# Record sha256 pins of the golden regression test and the git binary so the
# verifier can detect substitution, and lock /opt read-only for everyone.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_memory_zone.py > /opt/pins/golden.sha256 \
 && sha256sum /usr/bin/git > /opt/pins/git.sha256 \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/golden.sha256 /opt/pins/git.sha256 /opt/golden/test_memory_zone.py \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/git.sha256 >/dev/null \
 && echo "golden test + git pinned"

# The trial may run as root or as uid 1000 (user `ubuntu` exists in the base
# image). The agent must edit the sources and recompile, so the whole tree is
# owned by uid 1000 and world-readable.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]