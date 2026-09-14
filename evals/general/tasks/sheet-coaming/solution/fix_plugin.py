#!/usr/bin/env python3
"""Apply the upstream fix for the django_rawsql_used keyword-argument crash.

The checked-out django SQL-injection plugin reads the SQL text with an
unconditional ``sql = context.node.args[0]``; calling Django's RawSQL with the
SQL passed as a keyword argument (``RawSQL(sql=..., params=...)``) leaves args
empty and crashes the whole scan with IndexError, so the risky call is never
reported.  The upstream repair reads the ``sql`` keyword argument when there
are no positional arguments.

This script performs the real transformation on the checked-out source: it
replaces the unconditional indexing with a positional-arg guard whose else
branch resolves the ``sql`` keyword via the file's own ``keywords2dict``
helper.  It fails loudly if the pre-fix pattern is not found.
"""

import sys


def main(argv):
    plugin = argv[1]
    src = open(plugin, encoding="utf-8").read()

    old = (
        '        if context.call_function_name == "RawSQL":\n'
        "            sql = context.node.args[0]\n"
    )
    new = (
        '        if context.call_function_name == "RawSQL":\n'
        "            if context.node.args:\n"
        "                sql = context.node.args[0]\n"
        "            else:\n"
        "                kwargs = keywords2dict(context.node.keywords)\n"
        '                sql = kwargs["sql"]\n'
    )
    if old not in src:
        print("pre-fix pattern not found; aborting", file=sys.stderr)
        return 1
    src = src.replace(old, new, 1)
    with open(plugin, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("patched", plugin)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))