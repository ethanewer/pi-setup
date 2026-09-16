# capstan-ebb: real PyCQA/bandit cloned at the PARENT of upstream fix
# 3c56109 ("Fix B608 to detect `VALUES(` without space", issue #1336). The
# agent gets the genuine buggy tree, must reproduce, localise and fix it, and
# is never told the issue, the commit, or the file to change. The fix commit is
# never fetched into /app/src; the project's own regression assets (the
# fix-version example file and functional test file) are extracted into
# /opt/golden from a throwaway clone that is deleted immediately afterwards, so
# upstream test bytes never enter this task tree.
ARG UPSTREAM_SHA_PARENT=b790ce22f0a69f53468c1755e9d37e6349a2c8c2
ARG UPSTREAM_SHA_FIX=3c56109061524f5907cc4d475b7370bac47a451b
ARG GOLDEN_EXAMPLE_SHA256=4f0f942b6d774451745e7cfdf978ffa9420e4c075f587f6d6381b1b346ce79f7
ARG GOLDEN_TEST_SHA256=c708e836f60d17b91c288e838140f13ca235ac891c92b48bccab9f22e245e009

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GOLDEN_EXAMPLE_SHA256
ARG GOLDEN_TEST_SHA256

# Pinned dependency set (resolved against the base image's own interpreter at
# image build time). bandit's runtime deps, its build chain (pbr/setuptools/
# wheel) and its full test deps, including the baseline (GitPython) and sarif
# (sarif-om, jschema-to-python) extras that two unit-test modules import.
RUN pip install --no-cache-dir \
      PyYAML==6.0.3 \
      stevedore==5.9.1 \
      rich==15.0.0 \
      pbr==7.0.3 \
      setuptools==75.6.0 \
      wheel==0.45.1 \
      testtools==2.9.1 \
      fixtures==4.3.2 \
      testscenarios==0.7.0 \
      beautifulsoup4==4.15.0 \
      coverage==7.16.0 \
      GitPython==3.1.44 \
      sarif-om==1.0.4 \
      jschema-to-python==1.2.3

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned SHA
# means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which an agent must not be able to look up or fetch) is never fetched
# into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/PyCQA/bandit.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression assets for this bug into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so upstream
# bytes never land in this task tree and the fix commit never lands in
# /app/src. The functional regression test test_sql_statements asserts score
# counts for examples/sql_statements.py; the counts it expects only make sense
# with the fix-version example (which adds the VALUES( no-space lines), so BOTH
# files must come from the fix commit. Pinned sha256 hashes of the extracted
# bytes let the verifier detect tampering later.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/PyCQA/bandit.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:examples/sql_statements.py \
      > /opt/golden/sql_statements.py \
 && git show ${UPSTREAM_SHA_FIX}:tests/functional/test_functional.py \
      > /opt/golden/test_functional.py \
 && test "$(sha256sum /opt/golden/sql_statements.py | cut -d' ' -f1)" = "${GOLDEN_EXAMPLE_SHA256}" \
 && test "$(sha256sum /opt/golden/test_functional.py | cut -d' ' -f1)" = "${GOLDEN_TEST_SHA256}" \
 && grep -q "VALUES(" /opt/golden/sql_statements.py \
 && grep -q "test_sql_statements" /opt/golden/test_functional.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone, and that
# the object store holds nothing beyond the single parent commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list HEAD --count)" = "1" \
 && test "$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)" = "0"

# Editable install of the pinned tree: pbr builds with the preinstalled
# setuptools/wheel/pbr (no build isolation, no network at this step other than
# what pip already cached). bandit therefore imports straight from /app/src and
# an edit to the plain .py sources is picked up immediately, offline.
RUN cd /app/src \
 && pip install --no-cache-dir --no-build-isolation -e . \
 && cd /tmp \
 && python -c "import bandit; print('bandit editable at', bandit.__file__); assert bandit.__file__.startswith('/app/src')"

# Re-confirm BOTH directions inside this very image, then restore the pristine
# parent tree. (The mining container proved them already; this proves them
# under THIS image's pinned dependency set, so the oracle reward is real.)
#   parent direction: bandit finds NOTHING for "INSERT INTO foo VALUES(%s)"
#     (the no-space form slips through; results == []).
#   fix direction:    the one-line regex change makes the same scan report one
#     B608 finding (Severity: Medium, Confidence: Medium) at line 5, the
#     project's own regression test (fix-version example + test file) and the
#     whole functional module pass.
RUN cd /app/src \
 && printf '%s\n' \
      'import sqlite3' \
      "conn = sqlite3.connect('app.db')" \
      'cur = conn.cursor()' \
      "value = \"x' OR '1'='1\"" \
      'cur.execute("INSERT INTO foo VALUES(%s)" % value)' \
    > /tmp/values.py \
 && (bandit -f json /tmp/values.py > /tmp/parent.json 2>/dev/null || true) \
 && python3 -c 'import json; d=json.load(open("/tmp/parent.json")); \
    print("PARENT direction results:", [(r["test_id"], r["line_number"]) for r in d["results"]]); \
    assert d["results"] == [], d["results"]; \
    print("PARENT direction confirmed: no-space VALUES( INSERT is NOT flagged")' \
 && python3 -c 'import sys; \
    p = "bandit/plugins/injection_sql.py"; \
    s = open(p).read(); old = sys.argv[1]; new = sys.argv[2]; \
    assert s.count(old) == 1, "regex line not found in injection_sql.py"; \
    open(p, "w").write(s.replace(old, new)); print("applied one-line regex fix for re-confirmation")' \
    'r"insert\s+into\s.*values\s|"' \
    'r"insert\s+into\s.*values[\s(]|"' \
 && (bandit -f json /tmp/values.py > /tmp/fix.json 2>/dev/null || true) \
 && python3 -c 'import json; d=json.load(open("/tmp/fix.json")); \
    print("FIX direction results:", [(r["test_id"], r["line_number"], r["issue_severity"], r["issue_confidence"]) for r in d["results"]]); \
    assert any(r["test_id"] == "B608" and r["line_number"] == 5 \
               and r["issue_severity"] == "MEDIUM" and r["issue_confidence"] == "MEDIUM" \
               for r in d["results"]); \
    print("FIX direction confirmed: VALUES( now reported as B608 Medium/Medium")' \
 && cp /opt/golden/sql_statements.py examples/sql_statements.py \
 && cp /opt/golden/test_functional.py tests/functional/test_functional.py \
 && python3 -m unittest tests.functional.test_functional.FunctionalTests.test_sql_statements \
 && python3 -m unittest tests.functional.test_functional \
 && git checkout -- examples/sql_statements.py tests/functional/test_functional.py bandit/plugins/injection_sql.py \
 && test "$(git status --porcelain | wc -l)" = "0" \
 && rm -f /tmp/values.py /tmp/parent.json /tmp/fix.json \
 && echo "both directions re-confirmed inside this image and tree restored"

# The tree is kept writable for whatever uid (root or 1000) the trial runs as;
# the __pycache__ caches generated at build time are removed and .git is left
# untouched (working-tree edits are all the trial needs).
RUN find /app -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null; \
    chmod -R a+rwX /app \
 && chmod -R a+rwX /app/src

# Tripwire: the trial runs as root, so an agent could otherwise plant a
# sitecustomize.py or .pth file, or edit an installed dependency, to make
# bandit LOOK fixed while /app/src stays byte-identical (wrapper intercept,
# confirmed against this verifier before the tripwire existed: reward 1 with a
# pristine tree). Hash every interpreter-visible file (python sources, .pth,
# native modules) under /usr and /opt, excluding bytecode caches that imports
# regenerate, plus every regular file under /usr/local/bin (the bandit
# console script). The verifier recomputes these hashes and fails the trial if
# anything differs, so a fix has to live in /app/src where the scope check can
# hold it to the single bug's source file.
RUN { find /usr /opt -type f \( -name '*.py' -o -name '*.pth' -o -name '*.so' \) \
        -not -path '*/__pycache__/*' 2>/dev/null \
    | sort; \
    find /usr/local/bin -maxdepth 1 -type f 2>/dev/null | sort; } \
  | xargs -r sha256sum > /var/lib/usr-tripwire.sha256 \
 && test -s /var/lib/usr-tripwire.sha256 \
 && echo "tripwire manifest: $(wc -l < /var/lib/usr-tripwire.sha256) files hashed"

WORKDIR /app

CMD ["/bin/bash"]