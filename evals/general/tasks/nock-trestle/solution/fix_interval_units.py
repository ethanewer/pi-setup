#!/usr/bin/env python3
# Ground-truth fix for the seeded trino-parser regression: restores the
# correct mapping of the YEAR / MONTH interval-field tokens in the parser's
# AST builder. This is the same edit a competent agent produces: running the
# module's own interval tests shows that the YEAR and MONTH simple interval
# units are swapped, and the fix swaps them back.
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
sources = root / "core/trino-parser/src/main/java/io/trino/sql/parser/AstBuilder.java"

buggy = """                switch (context.field.getType()) {
                    case YEAR -> new IntervalField.Month();
                    case MONTH -> new IntervalField.Year();
                    default -> throw parseError("Unexpected year-month interval field: " + context.field.getText(), context);
                }"""
fixed = """                switch (context.field.getType()) {
                    case YEAR -> new IntervalField.Year();
                    case MONTH -> new IntervalField.Month();
                    default -> throw parseError("Unexpected year-month interval field: " + context.field.getText(), context);
                }"""

text = sources.read_text()
if buggy not in text:
    sys.exit("fix anchor not found in %s; tree state unexpected" % sources)
sources.write_text(text.replace(buggy, fixed, 1))
print("interval year/month field mapping restored")