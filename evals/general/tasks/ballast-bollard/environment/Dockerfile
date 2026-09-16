ARG UPSTREAM_SHA=7e6f580d6ad1b35be91046e591526602327a388d
ARG FIX_SHA=72fa5a7496caa89f21ace353d038754dbddf9a91

FROM bench-base:python-3.12

ARG UPSTREAM_SHA
ARG FIX_SHA

ENV PYTHONPYCACHEPREFIX=/tmp/pycache \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# git is needed once at build time: the project's pbr-based setup.py derives
# its version from the git metadata at install time.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*

# The real upstream tree, checked out at the buggy PARENT commit and pinned to
# the immutable 40-hex revision (shallow fetch of exactly that commit). The
# project is PyCQA/bandit, the security static analyser for Python.
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/PyCQA/bandit.git \
 && git -C /app/src fetch --depth 1 origin $UPSTREAM_SHA \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*'

# The project's own regression test for this defect, extracted verbatim from
# the FIX commit, plus the example file that test exercises. Kept out of the
# checked-out tree: /opt/golden is plain data, not git history, and the fetch
# below is the only moment the fix commit exists anywhere in this image.
RUN git -C /app/src fetch --depth 1 origin $FIX_SHA \
 && mkdir -p /opt/golden \
 && git -C /app/src show $FIX_SHA:tests/functional/test_functional.py \
      > /opt/golden/test_functional.py \
 && git -C /app/src show $FIX_SHA:examples/sql_multiline_statements.py \
      > /opt/golden/sql_multiline_statements.py \
 && test -s /opt/golden/test_functional.py \
 && test -s /opt/golden/sql_multiline_statements.py

# Project install: pbr needs setuptools/pbr/wheel and the git metadata, so
# install before the metadata is stripped. Runtime dependencies are pinned
# exactly; -e . then runs with --no-deps so nothing floats in later layers.
RUN pip install --no-cache-dir setuptools==84.0.0 pbr==7.0.3 wheel==0.48.0 \
 && pip install --no-cache-dir GitPython==3.1.62 PyYAML==6.0.3 stevedore==5.9.1 colorama==0.4.6 rich==15.0.0 \
 && cd /app/src \
 && pip install --no-cache-dir --no-deps --no-build-isolation -e . \
 && pip install --no-cache-dir fixtures==4.3.2 testscenarios==0.7.0 testtools==2.9.1 beautifulsoup4==4.15.0

# Strip the git metadata so the fix commit (and all history) is unreachable
# from the checkout the agent gets, and guarantee write access for whatever
# uid the trial container runs as.
RUN rm -rf /app/src/.git \
 && chmod -R a+rwX /app \
 && chmod -R a+rwX /opt

WORKDIR /app

COPY files/ /app/