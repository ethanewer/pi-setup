#!/usr/bin/env python3
"""Fix the DOMPurify URI-validation bypass in the checkout at argv[1].

Root cause (upstream issue #1320): in the per-attribute name-permission flow
of src/purify.ts, the function-form ADD_ATTR callback is consulted in an
early-exit branch placed BEFORE the value-level URI validation. An attribute
name the callback permits therefore jumps straight to "safe" and its value
never passes the URI whitelist, so href="javascript:alert(1)" survives as long
as the permission comes from a callback.

Fix: fold the callback result together with the ALLOWED_ATTR membership into a
single `nameIsPermitted` condition, computed up front, so a permitted name
still falls through to the shared value-validation tail.

This script applies exactly that transformation to src/purify.ts of the
checkout. It is the same change upstream shipped; it is applied here by the
reference solution (and by any correctly working agent) so the dangerous
schemes are stripped again while safe URIs and non-URI attributes survive.
"""

import re
import sys


def main() -> int:
    root = sys.argv[1]
    path = root + "/src/purify.ts"
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()

    # 1) Insert the nameIsPermitted computation right before the data-*
    #    allowance comment (after the node-clobber guard).
    old_anchor = """    /* Allow valid data-* attributes: At least one character after "-"
"""
    insert = (
        "    const nameIsPermitted =\n"
        "      ALLOWED_ATTR[lcName] ||\n"
        "      (EXTRA_ELEMENT_HANDLING.attributeCheck instanceof Function &&\n"
        "        EXTRA_ELEMENT_HANDLING.attributeCheck(lcName, lcTag));\n\n"
        + old_anchor
    )
    if old_anchor not in src:
        raise SystemExit("anchor block not found; src/purify.ts differs from expectation")
    if src.count(old_anchor) != 1:
        raise SystemExit("anchor block not unique; cannot patch safely")
    src = src.replace(old_anchor, insert, 1)

    # 2) Replace the callback early-exit branch: the name check now feeds the
    #    removal condition instead of exiting the permission chain early.
    old_branch = """      // This attribute is safe
      /* Check if ADD_ATTR function allows this attribute */
    } else if (
      EXTRA_ELEMENT_HANDLING.attributeCheck instanceof Function &&
      EXTRA_ELEMENT_HANDLING.attributeCheck(lcName, lcTag)
    ) {
      // This attribute is safe
      /* Otherwise, check the name is permitted */
    } else if (!ALLOWED_ATTR[lcName] || FORBID_ATTR[lcName]) {
"""
    new_branch = """      // This attribute is safe
      /* Otherwise, check the name is permitted */
    } else if (!nameIsPermitted || FORBID_ATTR[lcName]) {
"""
    if old_branch not in src:
        raise SystemExit("callback branch not found; src/purify.ts differs from expectation")
    if src.count(old_branch) != 1:
        raise SystemExit("callback branch not unique; cannot patch safely")
    src = src.replace(old_branch, new_branch, 1)

    if src.count("nameIsPermitted") < 2:
        raise SystemExit("patch did not take; nameIsPermitted present only %d times"
                         % src.count("nameIsPermitted"))

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)
    print("patched %s (nameIsPermitted occurrences: %d)" % (path, src.count("nameIsPermitted")))
    return 0


if __name__ == "__main__":
    sys.exit(main())