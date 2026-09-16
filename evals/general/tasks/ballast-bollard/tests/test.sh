#!/bin/bash
# Verifier for ballast-bollard: SWE-bench-shaped debugging task on the real
# PyCQA/bandit tree. The agent must repair the tree so that a `# nosec`
# comment anywhere in a multi-line construct's line range suppresses the
# finding, then write /app/diagnosis.md.
#
# Checks, in order:
#   1. the declared deliverable /app/diagnosis.md exists and names the real
#      module and cause (not a placeholder, not a copy of the prompt),
#   2. provenance: /app/src is the real bandit tree at the buggy revision
#      (marker sources present, git metadata absent, test files pristine),
#   3. the image's /opt/golden holds the project's OWN regression test and
#      example extracted from the upstream fix commit (checksums asserted so
#      a tampered golden copy is caught),
#   4. the project's own suites pass against the agent's tree: the golden
#      regression test, the whole functional suite, and the unit suite --
#      the last two prove the fix broke nothing else,
#   5. every hidden case: the authored construct with `# nosec` on a later
#      line must scan clean, and the same construct with the comment
#      stripped must STILL be flagged (so the fix did not just disable the
#      checks and the case genuinely exercises the code path).
# Reward is written on every exit path and is strictly a 0 or a 1.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
failures=0

echo "== ballast-bollard verifier =="

# ---- 0. the project's own binary must exist and run ------------------------
if ! bandit --version >/tmp/verifier_bandit_version.txt 2>&1; then
    echo "FAIL: bandit binary does not run; repair must happen in the real " >&2
    echo "      installed tree (/app/src)" >&2
    failures=1
fi

# ---- 1. deliverable: /app/diagnosis.md -------------------------------------
if [ ! -f /app/diagnosis.md ]; then
    echo "FAIL: deliverable /app/diagnosis.md missing" >&2
    failures=1
else
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
ok = (len(text.strip()) >= 100
      and "nosec" in low
      and any(k in low for k in ("multi-line", "multiline", "linerange",
                                 "line range", "first line", "closing line")))
if not ok:
    print("FAIL: /app/diagnosis.md does not identify the real module and "
          f"cause (len={len(text.strip())}, mentions nosec={'nosec' in low}, "
          f"mentions multiline/linerange="
          f"{any(k in low for k in ('multi-line', 'multiline', 'linerange', 'line range', 'first line', 'closing line'))})",
          file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (names module+cause)")
PY
    rc=$?
    if [ $rc -ne 0 ]; then
        failures=1
    fi
fi

# ---- 2. provenance: real bandit tree, no git metadata, pristine tests ------
if [ ! -f /app/src/bandit/core/tester.py ] \
   || [ ! -f /app/src/bandit/core/utils.py ] \
   || [ ! -d /app/src/examples ] \
   || [ ! -f /app/src/README.rst ]; then
    echo "FAIL: /app/src is not the bandit source tree" >&2
    failures=1
fi
if [ -d /app/src/.git ]; then
    echo "FAIL: git metadata left in /app/src: the tree must be a plain " >&2
    echo "      checkout, not history an agent can fetch answers from" >&2
    failures=1
fi
# The project's own test files must be byte-identical to the pristine parent
# tree (except tests/functional/test_functional.py, which the verifier
# replaces with the project's own regression test below). This catches an
# agent that edits tests to force a pass.
python3 - <<'PY'
import hashlib, sys
pristine = {
"tests/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
"tests/functional/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
"tests/functional/test_baseline.py": "188efb06297ee9801c15606f0a40a87c838f7b384d79299bbe2f56bbe7eda248",
"tests/functional/test_runtime.py": "b1e197f4c4fee08ad57a86c47edd7ac3caa1b3e0f20da257e2a3495804f1b6d4",
"tests/unit/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
"tests/unit/cli/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
"tests/unit/cli/test_baseline.py": "49e02c15eae088a7d35aa44ab8ce021218cdc2ec4f008f6491662118bec74de5",
"tests/unit/cli/test_config_generator.py": "878ab6638723a4ffdf8fc83109beb0e7570c91e6d80dcbd178c4dd9053daf294",
"tests/unit/cli/test_main.py": "1da9d30be72a94bbc5797a7a212e46c62fe3bda2e8e8a8006a29e9bad0383cab",
"tests/unit/core/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
"tests/unit/core/test_blacklisting.py": "be826c7f931617725b68a03bd905d2751f1c376c7aa7f33a5931d1b38dc52bb5",
"tests/unit/core/test_config.py": "454bcddc978e056341b66ee980a2ae8ecebe251af9c662a9dbfa6f240497a8e1",
"tests/unit/core/test_context.py": "6fd99da83c4b3fde0aa4988dfe9367d59ea10386cdb84b4fe1905a66cc65f4bc",
"tests/unit/core/test_docs_util.py": "089fbde6bb7884f6df94b7c15da7f474b8e5a2e38a538c845b462987163a8659",
"tests/unit/core/test_issue.py": "46fbe705c54f85aff782fcaa0d9356594dd9a8426900c7544c026d1243d7dc56",
"tests/unit/core/test_manager.py": "f3f32263926769082cadb5ef0b80de784953920c4a384b7d183afade284f968f",
"tests/unit/core/test_meta_ast.py": "7e662e50a321f221fc9a79619f942df9881bb03423c05f7a441c17599a2ebf16",
"tests/unit/core/test_test_set.py": "2d6ef1971cef2a9c938c9ab900466627f1f0f988d33b3caf44016cfac9ec5dc1",
"tests/unit/core/test_util.py": "69327f8b8c85aae645d5aa8b67e5d280f897673cdd08b4f603ab758bbcd20372",
"tests/unit/formatters/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
"tests/unit/formatters/test_csv.py": "f6ba5289ed3fdca4d8f728ffa1ad549a04f0847f0ed9b1f1ee88f1d60ddc77c1",
"tests/unit/formatters/test_custom.py": "fb580c2027d2c839f21f50f7387e9d36bac96ec44335f8d450ad9ba718097c7c",
"tests/unit/formatters/test_html.py": "9d72e57683639c742cbe4da2bfb40f7b33852d08cd3db7bb5da817abf3b478c6",
"tests/unit/formatters/test_json.py": "0ca1a6f461b502460729ad25ee2438e2dc1d71842c2296154298118bea1580c1",
"tests/unit/formatters/test_screen.py": "b5daafffc05a74f1a403c5f8701f8802758c4c7f7f0f140d6d08e4f6107e81ad",
"tests/unit/formatters/test_text.py": "2d87f227ae6564b5b00e9211ff49c526ddbae0e83e060ae354ba5b9cf0e296b1",
"tests/unit/formatters/test_xml.py": "29dbab10fbfcfaebfbe02d928b25bb1d37dd7fe65e22bea5f52a7c390a240af4",
"tests/unit/formatters/test_yaml.py": "9e75c3148130b169f0fd03150f79546fefd0995977e1bc9bb53264892f27f4fa",
}
bad = []
for rel, want in pristine.items():
    p = "/app/src/" + rel
    try:
        got = hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError as e:
        bad.append(rel + " (missing: %s)" % e)
        continue
    if got != want:
        bad.append(rel)
if bad:
    print("FAIL: pristine test files modified: %d (%s)" % (len(bad), "; ".join(bad[:5])), file=sys.stderr)
    sys.exit(1)
print("provenance: real tree, no .git, test files pristine")
PY
    rc=$?
    if [ $rc -ne 0 ]; then
        failures=1
    fi

# ---- 3. golden regression test: present and untampered ---------------------
GOLD1="4f579a26020d656171cf670bfeb1bede007177d5060af746f1e58c33867ff4fd"
GOLD2="acaca248c08e6938b399766c3be22de715d071179592aae0d69aa1e0922c0c37"
if [ ! -f /opt/golden/test_functional.py ] || [ ! -f /opt/golden/sql_multiline_statements.py ]; then
    echo "FAIL: /opt/golden is missing the project's regression test files" >&2
    failures=1
else
    h1=$(sha256sum /opt/golden/test_functional.py | awk '{print $1}')
    h2=$(sha256sum /opt/golden/sql_multiline_statements.py | awk '{print $1}')
    if [ "$h1" != "$GOLD1" ] || [ "$h2" != "$GOLD2" ]; then
        echo "FAIL: /opt/golden content does not match the upstream fix-commit " >&2
        echo "      files (tampered golden copy)" >&2
        failures=1
    else
        echo "golden: regression test files intact"
    fi
fi

# ---- 4. the project's own suites against the repaired tree -----------------
if [ $failures -eq 0 ]; then
    # Install the project's own regression test + example from the fix commit
    # into the tree, replacing whatever (pristine or agent-edited) test file
    # was there. The agent is told not to touch tests/ or examples/; either
    # way the verifier tests the real sources with the real regression test.
    cp /opt/golden/test_functional.py /app/src/tests/functional/test_functional.py
    cp /opt/golden/sql_multiline_statements.py /app/src/examples/sql_multiline_statements.py

    # 4a. the golden regression test, by its upstream name
    (
        cd /app/src &&
        PYTHONPATH=/app/src python3 -m unittest \
            tests.functional.test_functional.FunctionalTests.test_multiline_sql_statements
    ) > /tmp/verifier_golden.log 2>&1
    if [ $? -eq 0 ]; then
        echo "golden regression test: PASS"
    else
        echo "FAIL: golden regression test test_multiline_sql_statements failed" >&2
        tail -20 /tmp/verifier_golden.log >&2
        failures=1
    fi

    # 4b. the whole functional suite (includes the golden test)
    (
        cd /app/src &&
        PYTHONPATH=/app/src python3 -m unittest tests.functional.test_functional
    ) > /tmp/verifier_func.log 2>&1
    if [ $? -eq 0 ]; then
        echo "functional suite: PASS ($(grep -E '^(Ran |OK|FAILED)' /tmp/verifier_func.log | tr '\n' ' '))"
    else
        echo "FAIL: project functional suite does not pass" >&2
        tail -15 /tmp/verifier_func.log >&2
        failures=1
    fi

    # 4c. the unit suite (core + formatters + cli)
    (
        cd /app/src &&
        PYTHONPATH=/app/src python3 -m unittest discover -s tests/unit
    ) > /tmp/verifier_unit.log 2>&1
    if [ $? -eq 0 ]; then
        echo "unit suite: PASS ($(grep -E '^(Ran |OK|FAILED)' /tmp/verifier_unit.log | tr '\n' ' '))"
    else
        echo "FAIL: project unit suite does not pass" >&2
        tail -15 /tmp/verifier_unit.log >&2
        failures=1
    fi
else
    echo "note: project suites skipped because earlier checks failed" >&2
fi

# ---- 5. hidden cases: nosec on a later line must suppress, and only there --
mkdir -p /tmp/hidden_naked
for case_dir in /tests/hidden/*/; do
    scan="$case_dir/scan.py"
    [ -f "$scan" ] || continue
    name=$(basename "$case_dir")
    # the nosec-carrying file must scan clean on the repaired tree
    if bandit -q "$scan" > /tmp/verifier_hidden.log 2>&1; then
        echo "hidden $name: scan clean (PASS)"
    else
        echo "FAIL: hidden case $name still reports an issue despite # nosec" >&2
        grep -E "Issue:|Location:" /tmp/verifier_hidden.log | head -4 >&2
        failures=1
        continue
    fi
    # the same construct with the nosec stripped must STILL be flagged:
    # proves the case really exercises the code path and the fix did not
    # disable the checks.
    naked="/tmp/hidden_naked/${name}_naked.py"
    sed -E 's/#[[:space:]]*nosec.*$//' "$scan" > "$naked"
    if bandit -q "$naked" > /tmp/verifier_naked.log 2>&1; then
        echo "FAIL: hidden case $name: construct is not flagged without nosec" >&2
        echo "      (nothing reported on the stripped variant)" >&2
        failures=1
    else
        found=$(grep -c "Issue:" /tmp/verifier_naked.log)
        if [ "$found" -ge 1 ]; then
            echo "hidden $name: stripped variant still flagged ($found issue(s)) (PASS)"
        else
            echo "FAIL: hidden case $name: stripped variant exited nonzero without" >&2
            echo "      an Issue line (unexpected bandit failure?)" >&2
            tail -8 /tmp/verifier_naked.log >&2
            failures=1
        fi
    fi
done

# ---- reward -----------------------------------------------------------------
if [ $failures -eq 0 ]; then
    echo "VERIFIER: all checks passed, reward=1"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER: failures present, reward=0" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0