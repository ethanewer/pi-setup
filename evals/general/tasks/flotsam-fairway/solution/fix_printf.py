#!/usr/bin/env python3
"""Oracle fix for flotsam-fairway: apply the upstream fix for the printf %c
invalid-UTF-8 bug to the checkout at /app/src.

The fix is the one upstream made for duckdb/duckdb#25166 in
extension/core_functions/scalar/string/printf.cpp: after the format result is
built (in the code path shared by printf and format), validate it as UTF-8 and
raise a clean InvalidInputException when it is not, pointing the user at chr()
for writing code points. Anchored string edits only, so the function is
idempotent and fails loudly if the expected source is not where it should be.
"""

import subprocess
import sys

PATH = "/app/src/extension/core_functions/scalar/string/printf.cpp"

INCLUDE_ANCHOR = '#include "fmt/printf.h"\n'
INCLUDE_ADD = '#include "utf8proc_wrapper.hpp"\n'

RESULT_ANCHOR = "\t\tstring dynamic_result = FORMAT_FUN::template OP<CTX>(format_string.c_str(), current_args);\n"
VALIDATION_BLOCK = (
    "\t\tif (!Utf8Proc::IsValid(dynamic_result.c_str(), dynamic_result.size())) {\n"
    '\t\t\tthrow InvalidInputException("Invalid UTF8 produced by format string \\"%s\\" - note that %%c writes a "\n'
    '\t\t\t                            "single byte, use chr(...) to write a Unicode code point",\n'
    "\t\t\t                            format_string);\n"
    "\t\t}\n"
)

EXPECTED_PARENT_BLOB = "4f947e38ec6e2d84eba84b2ae1056258aab9d529"  # git blob of the pinned parent's printf.cpp


def git_blob_sha(path: str) -> str:
    return subprocess.check_output(
        ["git", "-C", "/app/src", "hash-object", path], text=True
    ).strip()


def main() -> int:
    original = open(PATH, "rb").read()
    text = original.decode("utf-8")

    if "Utf8Proc::IsValid(dynamic_result.c_str(), dynamic_result.size())" in text:
        print("printf.cpp already carries the UTF-8 validation; leaving it in place")
        return 0

    if git_blob_sha(PATH) != EXPECTED_PARENT_BLOB:
        print(
            "REFUSING: printf.cpp is not the pinned parent blob "
            "(%s != %s). Aborting instead of mangling an unexpected tree."
            % (git_blob_sha(PATH)[:12], EXPECTED_PARENT_BLOB[:12]),
            file=sys.stderr,
        )
        return 2

    if INCLUDE_ANCHOR not in text:
        print("REFUSING: include anchor not found", file=sys.stderr)
        return 2
    text = text.replace(INCLUDE_ANCHOR, INCLUDE_ANCHOR + INCLUDE_ADD, 1)

    if RESULT_ANCHOR not in text:
        print("REFUSING: format-result anchor not found", file=sys.stderr)
        return 2
    text = text.replace(RESULT_ANCHOR, RESULT_ANCHOR + VALIDATION_BLOCK, 1)

    with open(PATH, "w", encoding="utf-8") as fh:
        fh.write(text)

    print("patched printf.cpp: %s -> %s" % (EXPECTED_PARENT_BLOB[:12], git_blob_sha(PATH)[:12]))
    return 0


if __name__ == "__main__":
    sys.exit(main())