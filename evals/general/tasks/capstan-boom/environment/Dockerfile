# ---------------------------------------------------------------------------
# capstan-boom: semgrep's git URL parser fails to convert scp-like git remotes
# (no protocol prefix, no trailing ".git", dash in owner or repo name) into the
# https URL used to link report findings.
#
# The image clones semgrep/semgrep and checks out upstream PARENT commit
# bb89271f8418167b9d4cee2668e3d38a36003978 (immediately before upstream commit
# 483878b242d5217844af8b71068b60b495f34614 fixed issue #1503), so the agent
# gets the real repository with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. Neither the fix commit nor any
# later history is reachable from /app/src, so the agent cannot look the fix
# up from the clone. The one submodule the Python code needs
# (cli/src/semgrep/semgrep_interfaces, https://github.com/returntocorp/
# semgrep-interfaces) is initialised at build time because there is no network
# at trial time; it is not a Terminal-Bench repository (checked against
# specs/tb21_source_repositories.json by hand and by the disjointness gate).
# The golden-test extraction below uses a throwaway clone that is deleted, so
# the fix bytes never land in the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=bb89271f8418167b9d4cee2668e3d38a36003978
ARG FIX_SHA=483878b242d5217844af8b71068b60b495f34614

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/semgrep/semgrep.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && git -C /app/src submodule update --init cli/src/semgrep/semgrep_interfaces \
 && test "$(git -C /app/src/cli/src/semgrep/semgrep_interfaces rev-parse HEAD)" = "$(git -C /app/src ls-tree HEAD cli/src/semgrep/semgrep_interfaces | awk '{print $3}')" \
 && test -z "$(git -C /app/src status --porcelain)"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# file lives only in the image at /opt/golden/.
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/semgrep/semgrep.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:cli/tests/default/unit/test_meta.py \
      > /opt/golden/test_meta.py \
 && test -s /opt/golden/test_meta.py \
 && grep -q "def test_get_url_from_sstp_url" /opt/golden/test_meta.py \
 && grep -q "def test_git_url_parser" /opt/golden/test_meta.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_meta.py

# ---- runtime and test environment, fully pinned (the trial has no network) --
# The reproduction is pure Python (regex parsing): no semgrep-core binary, no
# compile step, no runtime fetches. semgrep's own cli/setup.py declares its
# dependencies with flexible specifiers; pip resolves them at build time and
# the era-appropriate editable install needs setuptools/wheel, pinned here.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install --no-cache-dir setuptools==72.0.0 wheel==0.44.0 pytest==8.3.5 \
 && cd /app/src/cli \
 && pip install -e . --no-build-isolation \
 && python3 -c "import semgrep, semgrep.external.git_url_parser; print('semgrep import ok:', semgrep.__file__)"

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]