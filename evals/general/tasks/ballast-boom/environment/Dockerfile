# ---------------------------------------------------------------------------
# ballast-boom: flake8's string redaction miscounts escaped braces in
# f-strings on Python 3.12, corrupting the logical line handed to plugins.
#
# The image clones PyCQA/flake8 and checks out upstream PARENT commit
# 2a811cc4d2aaed3e8eb5a9f04f08ccc8af7c0791 (immediately before upstream commit
# bdcd5c2c0afadaf7c92a4b26d96055cecdd38cf3 fixed issue #1948), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. See the golden-test extraction below,
# which uses a throwaway clone that is deleted, so the fix bytes never land in
# the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=2a811cc4d2aaed3e8eb5a9f04f08ccc8af7c0791
ARG FIX_SHA=bdcd5c2c0afadaf7c92a4b26d96055cecdd38cf3

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/PyCQA/flake8.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# file lives only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/PyCQA/flake8.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/integration/test_plugins.py \
      > /opt/golden/test_plugins.py \
 && test -s /opt/golden/test_plugins.py \
 && grep -q "def test_escaping_of_fstrings_in_string_redacter" /opt/golden/test_plugins.py \
 && test "$(sha256sum /opt/golden/test_plugins.py | cut -d' ' -f1)" = \
       "0d3181b38b4795bcf791a4463bd1897872a828e931548b1e1becbc16dce0ebc5" \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_plugins.py

# ---- runtime and test environment, fully pinned (the trial has no network) --
# flake8 is lint-only: no compiled extensions, no data fixtures, nothing
# fetched at runtime. Era dependencies resolve what the tree pins in setup.cfg
# (pycodestyle >=2.12.0,<2.13.0; pyflakes >=3.2.0,<3.3.0; mccabe >=0.7.0,<0.8.0).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# setuptools 72 is era-appropriate for this setup.cfg-only project (newer
# setuptools dropped [options]/[metadata] from setup.cfg); wheel is needed by
# the legacy editable install. Both are pinned like everything else.
RUN pip install pycodestyle==2.12.1 pyflakes==3.2.0 mccabe==0.7.0 pytest==8.3.5 \
            setuptools==72.0.0 wheel==0.44.0 \
 && cd /app/src \
 && pip install -e . --no-build-isolation

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]