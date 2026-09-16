# chainplate-chartroom: poetry config string interpolation treats falsy
# referenced values (0, False, "") as if the key were unset, leaving the
# literal {dotted.config.key} template in resolved values (upstream #10808).
#
# The image clones python-poetry/poetry SHALLOW at the PARENT commit (the
# real upstream bug is present in the working tree), extracts the project's
# own regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository), and overlays
# that fixed test file into the tree exactly as the mining reproduction did
# (`git checkout <fix> -- tests/config/test_config.py`), so the mined
# failing state is present from the first pytest run. The fix commit is
# fetched only into a throwaway bare clone that is deleted, so it is never
# reachable from /app/src (which additionally has no git remotes). poetry is
# neither on the frozen Terminal-Bench 2.1 source-repository list nor is the
# poetry-core git dependency; both checked against
# specs/tb21_source_repositories.json.
#
# The project is installed editable into /opt/poetry-venv, so the venv's
# `import poetry` resolves to the checked-out tree and the agent's edits take
# effect immediately. The build-time smoke run fails the image build unless
# the mined failing state is present.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

ARG UPSTREAM_SHA=e54180064368c2f9d9ad5ff4771d8b33538cc372
ARG FIX_SHA=e6f1ded9902d1fa17fc74e6562cb423e84fa7752

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of the default branch cannot contain the parent SHA, so
# fetch the parent by SHA, detach onto it and fail closed if upstream moves.
RUN git clone --depth 1 https://github.com/python-poetry/poetry.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin e54180064368c2f9d9ad5ff4771d8b33538cc372 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src' \
 && git remote remove origin

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/python-poetry/poetry.git \
 && git fetch --depth 1 origin e6f1ded9902d1fa17fc74e6562cb423e84fa7752 \
 && mkdir -p /opt/golden \
 && git show e6f1ded9902d1fa17fc74e6562cb423e84fa7752:tests/config/test_config.py \
      > /opt/golden/test_config.py \
 && test "$(sha256sum /opt/golden/test_config.py | cut -d' ' -f1)" \
      = "3f93019026b8546d337b53ba2dd264ff145dec187196d66b23d54d728f16359a" \
 && grep -q "def test_config_process_resolves_falsy_values" /opt/golden/test_config.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the corrected regression test into the working tree ------------
RUN cp /opt/golden/test_config.py /app/src/tests/config/test_config.py

# ---- install (editable, so the trial imports the repaired tree) -------------
# All versions below were resolved on bench-base:python-3.12 at authoring
# time; poetry-core is pinned to the git revision the upstream project needs.
RUN python3 -m venv /opt/poetry-venv \
 && /opt/poetry-venv/bin/pip install "poetry-core @ git+https://github.com/python-poetry/poetry-core.git@b9663e42c808543377ae523611c4cfad68016f30" \
 && cd /app/src && /opt/poetry-venv/bin/pip install -e . --no-deps \
 && /opt/poetry-venv/bin/pip install build==1.6.1 "cachecontrol[filecache]==0.14.4" \
      cleo==2.1.0 dulwich==1.2.14 fastjsonschema==2.22.2 installer==1.0.1 \
      keyring==25.7.0 packaging==26.3 pkginfo==1.13 platformdirs==4.11.8 \
      pyproject-hooks==1.2.0 requests==2.34.2 requests-toolbelt==1.0.0 \
      shellingham==1.5.4 tomlkit==0.15.1 trove-classifiers==2026.6.1.19 \
      virtualenv==21.7.9 findpython==0.8.0 "pbs-installer[download,install]==2026.9.1" \
      deepdiff==9.1.0 pytest==9.1.1 pytest-mock==3.15.1 \
      "pytest-xdist[psutil]==3.8.0" responses==0.26.3

# ---- build-time smoke: the mined failing state must reproduce --------------
# If the bug ever stops reproducing in this image (dependency drift, upstream
# rewrites history), the image build fails loudly instead of shipping a task
# whose oracle cannot pass.
RUN cd /app/src \
 && /opt/poetry-venv/bin/pytest tests/config/test_config.py \
      -k test_config_process_resolves_falsy_values --no-header -p no:randomly \
      -o addopts="" > /tmp/smoke.log 2>&1; \
    grep -qF "1 failed" /tmp/smoke.log

WORKDIR /app

# The build above ran as root; open the tree for whichever uid the trial
# uses. The repo's .gitignore covers the .pyc/.pytest_cache run artifacts,
# so a suite run leaves no untracked files in the tree.
RUN chmod -R a+rwX /app/src

COPY files/ /app/

CMD ["/bin/bash"]