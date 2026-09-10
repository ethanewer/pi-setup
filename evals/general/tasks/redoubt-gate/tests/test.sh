#!/bin/bash
# Verifier for redoubt-gate (executes-deliverable).
#
# The agent must repair /app/service so that ALL of the following hold:
#   1. `mvn -B -o -Dmaven.repo.local=/opt/m2repo verify` is green AND the
#      surefire reports show the shipped GreetingTest plus the two merged
#      hidden JUnit suites (HiddenGreetingTest, HiddenFormatterRestoredTest)
#      genuinely executed with zero failures and zero errors,
#   2. `mvn -B -o -Dmaven.repo.local=/opt/m2repo dependency:tree` resolves
#      exactly one version of com.example:formatter -- 1.0.0,
#   3. the project carries a maven-enforcer rule that fails the build if
#      com.example:formatter:2.0.0 can ever re-enter the dependency graph:
#      the verifier copies the project to /tmp/rg-neg, surgically restores
#      the conflict (undoes exclusions / dependencyManagement overrides /
#      direct formatter deps and re-adds the formatter:2.0.0 edge), then
#      requires `mvn -B -o -Dmaven.repo.local=/opt/m2repo validate` to exit
#      non-zero.
# Everything runs fully offline against the pre-seeded /opt/m2repo.
# Reward is strictly 0 or 1; this trap guarantees a reward on every path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if [ ! -f /app/service/pom.xml ]; then
  echo "FAIL: deliverable /app/service/pom.xml missing (no Maven project present)"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -d /app/service/src ]; then
  echo "FAIL: deliverable /app/service/src missing"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

OUT=$(python3 - <<'PY'
import glob
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

SERVICE = "/app/service"
M2 = "-Dmaven.repo.local=/opt/m2repo"
FAILURES = []


def fail(msg):
    FAILURES.append(msg)
    print("FAIL:", msg)


def run(cmd, cwd, timeout):
    try:
        return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    except FileNotFoundError:
        return None


def neutralize_pom(path):
    """Restore the canned conflict on a COPY of the project pom: strip any
    direct/dependencyManagement com.example:formatter dependency, strip any
    formatter exclusion, and re-add a direct formatter:2.0.0 edge (depth 1,
    so it beats every transitive path)."""
    with open(path, encoding="utf-8") as fh:
        src = fh.read()

    def drop_formatter_block(m):
        block = m.group(0)
        head = block.split("<exclusions>", 1)[0]
        if ("<groupId>com.example</groupId>" in head
                and "<artifactId>formatter</artifactId>" in head):
            return ""
        return block

    src = re.sub(r"(?s)<dependency>.*?</dependency>", drop_formatter_block, src)
    src = re.sub(
        r"(?s)<exclusion>\s*<groupId>com\.example</groupId>\s*"
        r"<artifactId>formatter</artifactId>.*?</exclusion>",
        "", src)
    sections = list(re.finditer(r"(?s)<dependencies>(.*?)</dependencies>", src))
    target = None
    for m in sections:
        if "junit-jupiter" in m.group(1) or "greeter" in m.group(1):
            target = m
            break
    if target is None:
        target = sections[0] if sections else None
    if target is None:
        raise SystemExit("neutralize: no <dependencies> section in " + path)
    direct = ("\n    <dependency>\n      <groupId>com.example</groupId>\n"
              "      <artifactId>formatter</artifactId>\n"
              "      <version>2.0.0</version>\n    </dependency>")
    src = src[:target.end(1)] + direct + "\n" + src[target.end(1):]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)


# ---------------------------------------------------------------------------
# 1. merge the hidden suites and require a fully offline green verify
# ---------------------------------------------------------------------------
merged = []
for case in sorted(p for p in os.listdir("/tests/hidden")
                   if os.path.isdir(os.path.join("/tests/hidden", p))):
    for f in sorted(glob.glob(os.path.join("/tests/hidden", case, "*.java"))):
        dst = os.path.join(SERVICE, "src/test/java/com/example/redoubtgate",
                           os.path.basename(f))
        shutil.copyfile(f, dst)
        merged.append(os.path.basename(f))
if not merged:
    fail("no hidden test sources under /tests/hidden")
    sys.exit(1)
print("merged %d hidden test source(s): %s" % (len(merged), ", ".join(merged)))

r = run(["mvn", "-q", "-B", "-o", M2, "verify"], SERVICE, 540)
if r is None:
    fail("mvn -q -B -o verify timed out or could not start")
    sys.exit(1)
if r.returncode != 0:
    tail = r.stdout.decode(errors="replace")[-3000:]
    fail("mvn -B -o verify failed (project does not build; the conflict is "
         "probably unresolved or the tests are red)")
    print(tail)
    sys.exit(1)

# -- the suites must have GENUINELY executed: parse the surefire reports.
reports = sorted(glob.glob(SERVICE + "/target/surefire-reports/TEST-*.xml"))
executed = 0
fails = 0
errors = 0
classes = set()
for rep in reports:
    try:
        root = ET.parse(rep).getroot()
    except Exception:
        continue
    executed += int(root.get("tests") or 0)
    fails += int(root.get("failures") or 0)
    errors += int(root.get("errors") or 0)
    for tc in root.iter("testcase"):
        cn = tc.get("classname") or ""
        classes.add(cn.rsplit(".", 1)[-1])
required = {"GreetingTest", "HiddenGreetingTest", "HiddenFormatterRestoredTest"}
if executed < 5 or fails or errors:
    fail("%d tests executed, %d failures, %d errors across %d surefire "
         "reports; need >= 5 executed with zero failures/errors"
         % (executed, fails, errors, len(reports)))
    sys.exit(1)
if not required.issubset(classes):
    missing = sorted(required - classes)
    fail("the shipped GreetingTest and both hidden suites must genuinely "
         "execute; missing classes: %s (classes seen: %s)"
         % (", ".join(missing), ", ".join(sorted(classes))))
    sys.exit(1)
print("surefire: %d tests executed, 0 failures, 0 errors; classes present:"
      " %s" % (executed, ", ".join(sorted(classes))))

# ---------------------------------------------------------------------------
# 2. exactly one formatter version in the resolved graph: 1.0.0
# ---------------------------------------------------------------------------
r = run(["mvn", "-B", "-o", M2, "dependency:tree"], SERVICE, 300)
if r is None:
    fail("mvn dependency:tree timed out or could not start")
    sys.exit(1)
if r.returncode != 0:
    fail("mvn -B -o dependency:tree failed")
    print(r.stdout.decode(errors="replace")[-1500:])
    sys.exit(1)
out = r.stdout.decode(errors="replace")
versions = sorted(set(re.findall(r"com\.example:formatter:jar:([0-9][^ :]*)", out)))
if versions != ["1.0.0"]:
    fail("dependency:tree must resolve exactly one version of "
         "com.example:formatter, namely 1.0.0; got: %s" % (versions or "none"))
    for line in out.splitlines():
        if "formatter" in line or "greeter" in line or "lib-y" in line:
            print("  tree|", line.strip())
    sys.exit(1)
print("dependency:tree resolves exactly com.example:formatter:1.0.0")

# ---------------------------------------------------------------------------
# 3. the enforcer rule must fail the build if the conflict returns
# ---------------------------------------------------------------------------
neg = "/tmp/rg-neg"
shutil.rmtree(neg, ignore_errors=True)
shutil.copytree(SERVICE, neg, dirs_exist_ok=True)
try:
    neutralize_pom(os.path.join(neg, "pom.xml"))
except SystemExit as e:
    fail("could not restore the conflict on the copy: %s" % e)
    sys.exit(1)
r = run(["mvn", "-q", "-B", "-o", M2, "validate"], neg, 300)
if r is None:
    fail("validate on the conflict-restored copy timed out or could not start")
    sys.exit(1)
if r.returncode == 0:
    fail("the build did NOT fail when com.example:formatter:2.0.0 was put "
         "back on the graph -- no effective maven-enforcer rule (validate "
         "exited 0)")
    print(r.stdout.decode(errors="replace")[-2000:])
    sys.exit(1)
print("enforcer: reintroduced conflict fails `mvn -B -o validate` (rc=%d)"
      % r.returncode)
shutil.rmtree(neg, ignore_errors=True)

if FAILURES:
    print("\n%d failure(s):" % len(FAILURES))
    sys.exit(1)
print("ALL PASS: offline verify green with merged hidden suites; exactly "
      "com.example:formatter:1.0.0 resolved; enforcer kills the build when "
      "the conflict returns")
sys.exit(0)
PY
)
RC=$?
printf '%s\n' "$OUT"

if [ "$RC" = "0" ]; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
exit 0