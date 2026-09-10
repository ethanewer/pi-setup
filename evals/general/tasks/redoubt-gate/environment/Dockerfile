# redoubt-gate: Maven transitive-dependency conflict (formatter 1.0.0 vs 2.0.0).
#
# The trial container has NO network, so the entire Maven world this task
# needs is pre-seeded into /opt/m2repo here at build time:
#   * the five com.example artifacts under /app/libsrc are built and
#     `mvn install`-ed into the repository,
#   * the JUnit 5.11.4 stack and the pinned lifecycle/dependency/enforcer
#     plugins are pulled by running the exact maven goals the trial runs,
#   * the build then REPLAYS the whole trial offline as a proof: the sick
#     service must FAIL `verify` (NoSuchMethodError), the reference-fixed
#     copy must PASS `verify`, exactly one formatter version must resolve
#     (1.0.0), and reintroducing the conflict must fail `validate` (the
#     enforcer rule fires).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        openjdk-21-jdk-headless maven >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    M2_REPO=/opt/m2repo

# Point Maven's global settings at the seeded repository too, so even a
# naked `mvn` (no -D flag) cannot silently try the network.
RUN python3 - <<'PY'
import xml.etree.ElementTree as ET
p = "/usr/share/maven/conf/settings.xml"
try:
    tree = ET.parse(p)
    root = tree.getroot()
except Exception:
    raise SystemExit("no global maven settings.xml at %s" % p)
for e in root.findall("localRepository"):
    root.remove(e)
lr = ET.SubElement(root, "localRepository")
lr.text = "/opt/m2repo"
tree.write(p, encoding="UTF-8", xml_declaration=True)
PY

WORKDIR /app
RUN chmod 777 /app
COPY files/ /app/

# ---- publish the com.example artifacts in dependency order (network
#      available now), then prove every artifact is fully cached offline ----
RUN set -e && \
    mkdir -p /opt/m2repo && \
    for d in formatter-1.0.0 formatter-2.0.0 conventions-1.0.0 greeter-2.0.0 lib-y-1.0.0; do \
        ( cd /app/libsrc/$d && mvn -q -B -Dmaven.repo.local=/opt/m2repo install >/dev/null 2>&1 ) || exit 1; \
    done && \
    echo "artifacts published; offline re-install proves they are fully cached" && \
    for d in formatter-1.0.0 formatter-2.0.0 conventions-1.0.0 greeter-2.0.0 lib-y-1.0.0; do \
        ( cd /app/libsrc/$d && mvn -q -B -o -Dmaven.repo.local=/opt/m2repo install >/dev/null 2>&1 ) || exit 1; \
    done

# ---- pull the junit stack + lifecycle plugins: online verify of the sick
#      service (it fails at the tests, which is the point) and an online
#      dependency:tree for the dependency plugin ----
RUN set -e && \
    ( cd /app/service && mvn -q -B -Dmaven.repo.local=/opt/m2repo verify >/dev/null 2>&1 || true ) && \
    ( cd /app/service && mvn -B -Dmaven.repo.local=/opt/m2repo dependency:tree >/dev/null 2>&1 ) && \
    echo "junit stack + lifecycle plugins cached"

# ---- build the reference-fixed copy (exclusion + enforcer rule) ----
RUN set -e && \
    rm -rf /tmp/fixed && cp -r /app/service /tmp/fixed && \
    python3 - <<'PY'
import re
p = "/tmp/fixed/pom.xml"
src = open(p, encoding="utf-8").read()

m = re.search(r"(?s)(<dependency>\s*<groupId>com\.example</groupId>\s*<artifactId>lib-y</artifactId>.*?</dependency>)", src)
if not m:
    raise SystemExit("forward: lib-y dependency block not found")
block = m.group(1)
excl = ('\n      <exclusions>\n        <exclusion>\n          <groupId>com.example</groupId>\n'
        '          <artifactId>formatter</artifactId>\n        </exclusion>\n      </exclusions>')
insert_at = block.rfind("</dependency>")
src = src.replace(block, block[:insert_at] + excl + "\n    " + block[insert_at:], 1)

m2 = re.search(r"(?s)(<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-enforcer-plugin</artifactId>.*?</plugin>)", src)
if not m2:
    raise SystemExit("forward: enforcer plugin block not found")
plug = m2.group(1)
exec_ = ('''
        <executions>
          <execution>
            <id>ban-formatter-2</id>
            <phase>validate</phase>
            <goals>
              <goal>enforce</goal>
            </goals>
            <configuration>
              <rules>
                <bannedDependencies>
                  <excludes>
                    <exclude>com.example:formatter:2.0.0</exclude>
                  </excludes>
                </bannedDependencies>
              </rules>
            </configuration>
          </execution>
        </executions>''')
insert_at = plug.rfind("</plugin>")
src = src.replace(plug, plug[:insert_at] + exec_ + "\n      " + plug[insert_at:], 1)
open(p, "w", encoding="utf-8").write(src)
PY

RUN set -e && echo "reference-fixed verify ONLINE (also pulls the enforcer plugin)" && ( cd /tmp/fixed && mvn -q -B -Dmaven.repo.local=/opt/m2repo verify >/tmp/fixed-online.log 2>&1 ) || { echo "FATAL: reference-fixed verify FAILED online" >&2; tail -40 /tmp/fixed-online.log >&2; exit 1; }; echo "reference-fixed verify passed online"

# ---- OFFLINE rehearsal of every state the trial can be in ----
RUN set -e && echo "PROOF 1/3: sick service MUST fail verify offline" && ( cd /app/service && mvn -q -B -o -Dmaven.repo.local=/opt/m2repo verify >/tmp/sick-offline.log 2>&1 ) && { echo "FATAL: the sick service PASSED verify offline; the shipped conflict does not break the build" >&2; tail -25 /tmp/sick-offline.log >&2; exit 1; } ; echo "PROOF 2/3: reference-fixed service MUST pass verify offline" && ( cd /tmp/fixed && mvn -q -B -o -Dmaven.repo.local=/opt/m2repo verify >/tmp/fixed-offline.log 2>&1 ) || { echo "FATAL: the reference-fixed service FAILED verify offline" >&2; tail -40 /tmp/fixed-offline.log >&2; exit 1; } ; ( cd /app/service && mvn -B -o -Dmaven.repo.local=/opt/m2repo dependency:tree >/tmp/sick-tree-offline.log 2>&1 ) && ( cd /tmp/fixed && mvn -B -o -Dmaven.repo.local=/opt/m2repo dependency:tree >/tmp/fixed-tree-offline.log 2>&1 ) && echo "PROOF 2b/3: the fixed graph must resolve exactly com.example:formatter:1.0.0" && { [ "$(grep -o 'com.example:formatter:jar:[0-9][^ :]*' /tmp/fixed-tree-offline.log | sed 's/.*://' | sort -u | tr '\n' ' ')" = "1.0.0 " ] || { echo "FATAL: fixed dependency:tree does not resolve exactly com.example:formatter:1.0.0" >&2; exit 1; }; } && echo "PROOF 2c/3: the sick graph must resolve 2.0.0 (the wrong one wins)" && { [ "$(grep -o 'com.example:formatter:jar:[0-9][^ :]*' /tmp/sick-tree-offline.log | sed 's/.*://' | sort -u | tr '\n' ' ')" = "2.0.0 " ] || { echo "FATAL: sick dependency:tree does not resolve com.example:formatter:2.0.0 (mechanism broken)" >&2; exit 1; }; } && echo "dependency trees asserted for both states"

RUN set -e && \
    rm -rf /tmp/fixed-bad && cp -r /tmp/fixed /tmp/fixed-bad && \
    python3 - <<'PY'
import re
p = "/tmp/fixed-bad/pom.xml"
src = open(p, encoding="utf-8").read()

def drop_formatter_block(m):
    block = m.group(0)
    head = block.split("<exclusions>", 1)[0]
    if "<groupId>com.example</groupId>" in head and "<artifactId>formatter</artifactId>" in head:
        return ""
    return block

src = re.sub(r"(?s)<dependency>.*?</dependency>", drop_formatter_block, src)
src = re.sub(r"(?s)<exclusion>\s*<groupId>com\.example</groupId>\s*<artifactId>formatter</artifactId>.*?</exclusion>", "", src)
sections = list(re.finditer(r"(?s)<dependencies>(.*?)</dependencies>", src))
target = None
for m in sections:
    if "junit-jupiter" in m.group(1) or "greeter" in m.group(1):
        target = m
        break
if target is None:
    target = sections[0] if sections else None
if target is None:
    raise SystemExit("probe: no <dependencies> section")
direct = ("\n    <dependency>\n      <groupId>com.example</groupId>\n"
          "      <artifactId>formatter</artifactId>\n"
          "      <version>2.0.0</version>\n    </dependency>")
src = src[:target.end(1)] + direct + "\n" + src[target.end(1):]
open(p, "w", encoding="utf-8").write(src)
PY

RUN set -e && echo "PROOF 3/3: reintroduced conflict MUST fail validate offline" && ( cd /tmp/fixed-bad && mvn -q -B -o -Dmaven.repo.local=/opt/m2repo validate >/tmp/probe-validate.log 2>&1 ) && { echo "FATAL: reintroduced conflict did NOT fail validate; enforcer rule ineffective" >&2; tail -25 /tmp/probe-validate.log >&2; exit 1; } ; rm -rf /tmp/fixed /tmp/fixed-bad /tmp/sick-offline.log /tmp/fixed-offline.log /tmp/sick-tree-offline.log /tmp/fixed-tree-offline.log /tmp/probe-validate.log /tmp/fixed-online.log && chmod -R a+rwX /opt/m2repo && echo "seed complete: /opt/m2repo is fully offline-capable; all three proofs passed"