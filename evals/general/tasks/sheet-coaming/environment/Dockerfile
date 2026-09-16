# ---------------------------------------------------------------------------
# sheet-coaming: bandit logs "Bandit internal error running:
# django_rawsql_used ... list index out of range" and never reports the risky
# call when Django's raw-SQL expression helper is called with the SQL text
# passed as a keyword argument instead of as the first positional argument.
#
# The image clones PyCQA/bandit and checks out upstream PARENT commit
# 6d6ec6d550ef3ce1c7b6b04a56931bac65e94f71 (immediately before upstream commit
# c420d1d5356f6979b7af3cc46bd182f3ac9edaeb fixed issue #764 via PR #765), so
# the agent gets the real repository with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. Neither the fix commit nor any
# later history is reachable from /app/src. No fix-commit bytes exist in this
# image at all: the upstream regression material (the fix-commit revision of
# tests/functional/test_functional.py and its example) is RECONSTRUCTED at
# verify time from the pristine parent tree at /opt/pretree (the fix commit
# only changed two example lines and one expected count there, so the
# reconstruction is byte-exact and sha-pinned by the verifier).
#
# A pristine copy of the buggy parent tree is kept at /opt/pretree so the
# verifier can prove the agent's own reproduction fails against the pre-fix
# code and passes against the repaired tree.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=6d6ec6d550ef3ce1c7b6b04a56931bac65e94f71
ARG FIX_SHA=c420d1d5356f6979b7af3cc46bd182f3ac9edaeb

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/PyCQA/bandit.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- pristine pre-fix tree for the verifier's two-tree checks ---------------
# Captured before any package install so it contains only the parent tree.
# Content-pinned: the decision-relevant plugin file and the two files the
# verifier reconstructs the regression material from must keep the exact
# bytes of the parent revision, so a tampered /opt/pretree cannot invalidate
# the pre-fix checks or poison the reconstruction.
RUN cp -a /app/src /opt/pretree \
 && chmod -R a+rX /opt/pretree \
 && test "$(git -C /opt/pretree rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(sha256sum /opt/pretree/bandit/plugins/django_sql_injection.py | cut -d' ' -f1)" = \
        "1193a0a0a1156cf4c882175b2270df6d5c110caad0e6da64dbb98e0e6866372f" \
 && test "$(sha256sum /opt/pretree/tests/functional/test_functional.py | cut -d' ' -f1)" = \
        "208ee4d5c1bb7211a556507d0f8e4b99200161f4ddadac0cbd4897f6aa855327" \
 && test "$(sha256sum /opt/pretree/examples/django_sql_injection_raw.py | cut -d' ' -f1)" = \
        "d0fbe7d31f736ea1a7d2d259646d1f323b9fb56df74f1dd0e80757bf098ba311"

# ---- belt: fix commit unreachable from the trial clone, exactly 1 commit ----
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! find /opt/pretree /app -name '*.py' -print0 | xargs -0 grep -lF 'RawSQL(sql=' >/dev/null 2>&1 \
 && ! find / -maxdepth 3 -name '.git' | grep -q fixsrc

# ---- runtime and test environment, fully pinned (the trial has no network) --
# bandit at this commit is pure Python: no compiled extensions, nothing fetched
# at runtime. pbr computes the install version from the git tree (setup.py is
# `setuptools.setup(pbr=True)`), so git must exist and the clone must be in
# place BEFORE the editable installs run -- which it is.
# The project's own test suite (stestr) needs: coverage, fixtures, stestr,
# testscenarios, testtools, beautifulsoup4 (requirements of the test runner
# stack). All resolved against bench-base:python-3.12 and pinned.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN pip install setuptools==84.0.0 pbr==7.0.3 wheel==0.48.0 \
        stevedore==5.9.1 PyYAML==6.0.3 rich==15.0.0 \
        GitPython==3.1.62 sarif-om==1.0.4 jschema-to-python==1.2.3 \
        coverage==7.16.0 fixtures==4.3.2 stestr==4.2.1 testscenarios==0.7.0 \
        testtools==2.9.1 beautifulsoup4==4.15.0 pytest==8.3.5 \
 && cd /app/src \
 && pip install --no-build-isolation -e . \
 && pip install --no-build-isolation -e '.[baseline]' \
 && pip freeze > /dev/null \
 && cd / && python3 -c "import bandit; print(bandit.__file__)"

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]