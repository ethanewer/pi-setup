# chandlery-waypoint: flake8 aborts with FileNotFoundError before linting when
# $HOME names a directory that does not exist (real upstream issue PyCQA/flake8
# #1642; the regression test for it, test_find_config_ignores_unknown_homedir,
# was added by the fix commit 8b51ee4).
#
# The image ships the real PyCQA/flake8 checkout SHALLOW at the PARENT commit
# (the bug is present in the working tree) at /app/src, pip-installed editable
# with the era dependency pins the mining phase verified (pycodestyle 2.9.1,
# pyflakes 2.5.0, mccabe 0.7.0, pytest 7.4.4) so the CLI and its plugins work.
# The project's own regression test is extracted from the FIX commit at build
# time through a throwaway bare clone under /tmp which is deleted afterwards,
# so the fix commit object never enters the shipped repository (asserted down
# the file); the golden file lives only at /opt/golden and is used solely by
# the verifier -- it is never overlaid into the agent's tree, because this task
# requires the agent to write its own reproduction. A second pristine snapshot
# of the parent tree (also without the fix object) sits at /opt/flake8-pristine
# as the verifier's pre-fix reference. flake8 is not a Terminal-Bench 2.1
# source repository (checked against specs/tb21_source_repositories.json; no
# submodules are fetched).
FROM bench-base:python-3.12

ARG PARENT_SHA=446b18d35a5fa0be6b3531d30a0706fc82247313
ARG FIX_SHA=8b51ee4ea54241f85df23f3dd20390b1563d4521
# content hashes let the build fail closed if upstream ever moves or mutates
ARG PARENT_CONFIG_SHA=15232151756a2a0b6fdb849946fad53c57dc74018d299a1412c2a01d9076a974
ARG PARENT_TESTFILE_SHA=9630d2bcebcc6ad0da7ef26d355892cde3d04b5ddbe7e3ee339489fe1aa9bb9c
ARG GOLDEN_TESTFILE_SHA=2844daa634b987f75cf18e79eeba5de53766b492cce81cb12db6dd17ad5a21ef

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- pinned runtime + test dependencies (the era set the mining phase used) --
RUN pip install --no-cache-dir \
        pycodestyle==2.9.1 \
        pyflakes==2.5.0 \
        mccabe==0.7.0 \
        pytest==7.4.4

# ---- working clone: parent commit, fix commit AND any post-fix tree unreachable ---
# We deliberately do NOT clone a branch: a depth-1 clone of `main` would carry
# the current (post-fix) tip's tree, letting an agent read the answer from
# `git show <main-tip>:src/...` with no network. Fetching the parent commit by
# bare SHA puts exactly one commit and only its (buggy) blobs in the store.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/PyCQA/flake8.git \
 && git fetch --depth 1 origin 446b18d35a5fa0be6b3531d30a0706fc82247313 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$PARENT_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git log --all --oneline | wc -l)" = "1" \
 && test "$(git show HEAD:src/flake8/options/config.py | grep -c 'except OSError' || true)" = "0" \
 && test "$(sha256sum src/flake8/options/config.py | cut -d' ' -f1)" = "$PARENT_CONFIG_SHA" \
 && echo "working tree at $PARENT_SHA; fix commit absent; no other refs"

# ---- editable install from the shipped tree; the tree must stay pristine ------
RUN cd /app/src && pip install --no-cache-dir -e . \
 && rm -rf src/flake8.egg-info \
 && test -z "$(git status --porcelain)" \
 && echo "flake8 installed editable; tree clean"

# artifacts the agent's own test runs create must not show up in `git status`
# (the verifier inspects the porcelain): keep them out via .git/info/exclude.
RUN printf '__pycache__/\n.pytest_cache/\n' >> /app/src/.git/info/exclude

# ---- pristine pre-fix snapshot used by the verifier ---------------------------
# Same parent commit, same pure parent-era test files; its config.py must equal
# the parent-era hash so a drifted or tampered reference fails the build.
RUN cp -a /app/src /opt/flake8-pristine \
 && test "$(git -C /opt/flake8-pristine rev-parse HEAD)" = "$PARENT_SHA" \
 && ! git -C /opt/flake8-pristine cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(sha256sum /opt/flake8-pristine/src/flake8/options/config.py | cut -d' ' -f1)" = "$PARENT_CONFIG_SHA" \
 && test "$(sha256sum /opt/flake8-pristine/tests/unit/test_options_config.py | cut -d' ' -f1)" = "$PARENT_TESTFILE_SHA" \
 && echo "pristine snapshot ready"

# ---- extract the upstream regression test from the FIX commit -----------------
# Throwaway bare clone, so the fix commit never exists inside any shipped .git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/PyCQA/flake8.git \
 && git fetch --depth 1 origin 8b51ee4ea54241f85df23f3dd20390b1563d4521 \
 && test "$(git rev-parse FETCH_HEAD)" = "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show 8b51ee4ea54241f85df23f3dd20390b1563d4521:tests/unit/test_options_config.py \
      > /opt/golden/test_options_config.py \
 && test "$(sha256sum /opt/golden/test_options_config.py | cut -d' ' -f1)" = "$GOLDEN_TESTFILE_SHA" \
 && grep -q "def test_find_config_ignores_unknown_homedir" /opt/golden/test_options_config.py \
 && cd / && rm -rf /tmp/fixsrc \
 && echo "golden regression test extracted; fix clone deleted"

# ---- re-confirm both directions inside this image (fail closed) ---------------
# Direction 1 (bug present): the golden test FAILS against the parent tree with
# the mined symptom (FileNotFoundError from _stat_key on the missing home), and
# the CLI crashes the same way with HOME pointing at a nonexistent directory.
RUN cp -a /app/src /tmp/smoke-bug \
 && cp /opt/golden/test_options_config.py /tmp/smoke-bug/tests/unit/test_options_config.py \
 && cd /tmp/smoke-bug \
 && PYTHONPATH=/tmp/smoke-bug/src python3 -m pytest tests/unit/test_options_config.py -q \
      > /tmp/smoke-bug.log 2>&1; \
    grep -qF "1 failed, 23 passed" /tmp/smoke-bug.log \
 && grep -q "FileNotFoundError" /tmp/smoke-bug.log \
 && cd /tmp \
 && HOME=/nonexistent-away PYTHONPATH=/app/src/src python3 -m flake8 --version \
      > /tmp/smoke-cli-bug.log 2>&1; \
    rc=$?; [ "$rc" -ne 0 ] \
 && grep -q "FileNotFoundError" /tmp/smoke-cli-bug.log \
 && rm -rf /tmp/smoke-bug \
 && echo "direction 1 ok: golden test and CLI both fail with FileNotFoundError at parent"

# Direction 2 (fixed): with the minimal honest fix applied to a COPY, the golden
# test and the rest of the project's unit suite pass, and the CLI works with a
# missing HOME. Nothing here ever fetches or applies the upstream fix commit.
RUN cp -a /app/src /tmp/smoke-fixed \
 && python3 - <<'PYEOF'
path = "/tmp/smoke-fixed/src/flake8/options/config.py"
src = open(path).read()
old = '    home_stat = _stat_key(home) if home != "~" else None\n'
assert src.count(old) == 1, "expected exactly one buggy home-stat line"
new = (
    "    try:\n"
    "        home_stat = _stat_key(home) if home != \"~\" else None\n"
    "    except OSError:  # FileNotFoundError / PermissionError / etc.\n"
    "        home_stat = None\n"
)
open(path, "w").write(src.replace(old, new))
PYEOF

RUN cp /opt/golden/test_options_config.py /tmp/smoke-fixed/tests/unit/test_options_config.py \
 && cd /tmp/smoke-fixed \
 && PYTHONPATH=/tmp/smoke-fixed/src python3 -m pytest tests/unit -q -k "not test_undefined_local_code" \
      > /tmp/smoke-fixed.log 2>&1; \
    grep -q "passed" /tmp/smoke-fixed.log \
 && ! grep -qE "failed|error" /tmp/smoke-fixed.log \
 && cd /tmp \
 && HOME=/nonexistent-away PYTHONPATH=/tmp/smoke-fixed/src python3 -m flake8 --version \
      > /tmp/smoke-cli-fixed.log 2>&1 \
 && grep -q "5.0.1" /tmp/smoke-cli-fixed.log \
 && rm -rf /tmp/smoke-fixed /tmp/smoke-bug.log /tmp/smoke-cli-bug.log \
 && echo "direction 2 ok: golden + unit suite pass, CLI works with missing HOME after the fix"

# reopen the working tree for whichever uid the trial uses
RUN chmod -R a+rwX /app/src \
 && chmod -R a+rX /opt/flake8-pristine /opt/golden

WORKDIR /app

CMD ["/bin/bash"]