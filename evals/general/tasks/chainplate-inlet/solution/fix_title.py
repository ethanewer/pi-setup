#!/usr/bin/env python3
"""Fix MixedLMResults.summary() so it honors the caller's title argument.

The summary method documents "title : str, optional -- If not None, then this
replaces the default title" but unconditionally calls

    smry.add_title("Mixed Linear Model Regression Results")

so every caller's title is silently discarded. The fix (identical in shape to
the upstream change) fills in the default title only when title is None and
passes the caller's title through to add_title():

    if title is None:
        title = "Mixed Linear Model Regression Results"
    smry.add_title(title)

Usage: fix_title.py [path-to-mixed_linear_model.py]
"""
import pathlib
import sys

DEFAULT = "/app/src/statsmodels/regression/mixed_linear_model.py"

OLD = """        smry.add_dict(info)
        smry.add_title("Mixed Linear Model Regression Results")
"""

NEW = """        smry.add_dict(info)
        if title is None:
            title = "Mixed Linear Model Regression Results"
        smry.add_title(title)
"""


def main() -> int:
    target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    text = target.read_text()
    if NEW in text:
        print(f"ok: {target} already honors the summary title argument")
        return 0
    if OLD not in text:
        print(f"error: could not locate the summary title site in {target}",
              file=sys.stderr)
        return 1
    target.write_text(text.replace(OLD, NEW, 1))
    print(f"ok: applied the title-honoring fix to {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())