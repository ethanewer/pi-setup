#!/usr/bin/env python3
"""neutralize.py -- restore THE redoubt-gate conflict onto a copy of the
project, so the enforcer rule can be proven to fire.

Given a path to a pom.xml (of a COPY of the project -- never the live one),
it undoes every legitimate resolution an agent may have shipped and puts a
com.example:formatter:2.0.0 edge back on the graph as a direct dependency
(depth 1, so it beats every transitive path):

  1. drops any direct <dependency> for com.example:formatter,
  2. drops any com.example:formatter entry inside <dependencyManagement>,
  3. drops any <exclusion> of com.example:formatter,
  4. inserts a direct <dependency> com.example:formatter:2.0.0 into the
     project's own <dependencies> section (the one carrying the greeter /
     junit deps).

Use from /solution via `python3 /solution/neutralize.py <pom>`.
"""
import re
import sys


def neutralize(path):
    with open(path, encoding="utf-8") as fh:
        src = fh.read()

    # 1+2. drop dependency blocks for com.example:formatter (anywhere:
    # direct dependencies or dependencyManagement entries).  The check uses
    # only the block head (up to any <exclusions>) so an exclusion of
    # formatter inside another artifact's block (e.g. lib-y) is not
    # mistaken for a formatter dependency.
    def drop_formatter_block(m):
        block = m.group(0)
        head = block.split("<exclusions>", 1)[0]
        if ("<groupId>com.example</groupId>" in head
                and "<artifactId>formatter</artifactId>" in head):
            return ""
        return block

    src = re.sub(r"(?s)<dependency>.*?</dependency>", drop_formatter_block, src)

    # 3. drop exclusions referencing com.example:formatter.
    src = re.sub(
        r"(?s)<exclusion>\s*<groupId>com\.example</groupId>\s*"
        r"<artifactId>formatter</artifactId>.*?</exclusion>",
        "", src)

    # 4. re-add a direct formatter 2.0.0 dependency into the project's own
    #    <dependencies> section (identified by its junit/greeter contents).
    sections = list(re.finditer(r"(?s)<dependencies>(.*?)</dependencies>", src))
    target = None
    for m in sections:
        if "junit-jupiter" in m.group(1) or "greeter" in m.group(1):
            target = m
            break
    if target is None:
        target = sections[0] if sections else None
    if target is None:
        raise SystemExit("neutralize: no <dependencies> section in %s" % path)
    direct = ("\n    <dependency>\n      <groupId>com.example</groupId>\n"
              "      <artifactId>formatter</artifactId>\n"
              "      <version>2.0.0</version>\n    </dependency>")
    src = src[:target.end(1)] + direct + "\n" + src[target.end(1):]

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: neutralize.py <pom.xml>")
    neutralize(sys.argv[1])