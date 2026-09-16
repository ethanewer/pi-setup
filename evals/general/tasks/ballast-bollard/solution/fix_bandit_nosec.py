"""Ballast-bollard oracle: repair Bandit's # nosec lookup so a suppression
comment anywhere in a finding's line range is honoured.

The defect: `BanditTester._get_nosecs_from_contexts` consults
`nosec_lines.get(context['lineno'])` - only the very first line of the node -
even though `context['linerange']` already carries every line the construct
spans. A `# nosec` on the closing or any middle line was therefore ignored and
the finding was still reported. This script ports the upstream fix (three
small edits to the scanner core):

  1. add utils.get_nosec(nosec_lines, context), which returns the nosec set
     for the first line of the construct's line range that actually has one,
  2. use it for the context lookup in tester._get_nosecs_from_contexts,
  3. move the "nosec used without a test number" bookkeeping out of the
     pre-visit phase and into the test phase, where a blanket nosec found
     anywhere in the line range is counted once per skipped test result
     instead of once per visited AST node (the old pre-visit check ran per
     node and double-counted f-string parts).

Each edit is applied only when the expected buggy text occurs exactly once, so
a tree that was already repaired (or changed beneath us) fails loudly instead
of being double-patched.
"""
import io
import sys

ROOT = "/app/src"


def patch(path, old, new, count=1):
    full = ROOT + path
    with io.open(full, encoding="utf-8") as f:
        src = f.read()
    n = src.count(old)
    if n != count:
        raise SystemExit(
            "oracle: expected %d occurrence(s) of a marker block in %s, "
            "found %d" % (count, path, n)
        )
    with io.open(full, "w", encoding="utf-8") as f:
        f.write(src.replace(old, new))


def main():
    # 1. utils.py: add the linerange-aware lookup at the end of the module.
    patch(
        "/bandit/core/utils.py",
        "    raise TypeError(\"Error: %s is not a valid node type in AST\" % name)\n",
        "    raise TypeError(\"Error: %s is not a valid node type in AST\" % name)\n"
        "\n\n"
        "def get_nosec(nosec_lines, context):\n"
        "    \"\"\"Return the nosec tests to skip for a context, scanning the\n"
        "    whole line range of the construct, not just its first line.\"\"\"\n"
        "    for lineno in context[\"linerange\"]:\n"
        "        nosec = nosec_lines.get(lineno, None)\n"
        "        if nosec is not None:\n"
        "            return nosec\n"
        "    return None\n",
    )

    # 2. node_visitor.py: drop the pre-visit blanket-nosec check (it only
    #    looked at the node's first line and double-counted multi-part nodes).
    patch(
        "/bandit/core/node_visitor.py",
        '        if hasattr(node, "lineno"):\n'
        '            self.context["lineno"] = node.lineno\n'
        "\n"
        "            # explicitly check for empty set to skip all tests for a line\n"
        "            nosec_tests = self.nosec_lines.get(node.lineno)\n"
        "            if nosec_tests is not None and not len(nosec_tests):\n"
        '                LOG.debug("skipped, nosec without test number")\n'
        "                self.metrics.note_nosec()\n"
        "                return False\n"
        "\n"
        '        if hasattr(node, "col_offset"):',
        '        if hasattr(node, "lineno"):\n'
        '            self.context["lineno"] = node.lineno\n'
        "\n"
        '        if hasattr(node, "col_offset"):',
    )

    # 3. tester.py: count a blanket nosec found late in the line range as a
    #    nosec (not as a skipped test), and consult the whole line range.
    patch(
        "/bandit/core/tester.py",
        "                        if not nosec_tests_to_skip or (\n"
        "                            result.test_id in nosec_tests_to_skip\n"
        "                        ):\n"
        '                            LOG.debug(\n'
        '                                "skipped, nosec for test %s" % result.test_id\n'
        "                            )\n"
        "                            self.metrics.note_skipped_test()\n"
        "                            continue",
        "                        if not nosec_tests_to_skip:\n"
        '                            LOG.debug("skipped, nosec without test number")\n'
        "                            self.metrics.note_nosec()\n"
        "                            continue\n"
        "                        elif result.test_id in nosec_tests_to_skip:\n"
        '                            LOG.debug(\n'
        '                                "skipped, nosec for test %s" % result.test_id\n'
        "                            )\n"
        "                            self.metrics.note_skipped_test()\n"
        "                            continue",
    )
    patch(
        "/bandit/core/tester.py",
        '        context_tests = self.nosec_lines.get(context["lineno"], None)',
        "        context_tests = utils.get_nosec(self.nosec_lines, context)",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())