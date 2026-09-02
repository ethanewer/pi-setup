#!/usr/bin/env python3
"""Static checks on the agent's /app/fix.sh.

Verifies (1) a valid shebang line, (2) LF-only line endings (no CR bytes), and
(3) that the script's syntax stays on the allowed-command allowlist -- i.e. it
contains no command substitution, no backticks, and none of the blocked utility
words. Exit status 0 when all checks pass, 1 otherwise.
"""
import re
import sys

FIX = "/app/fix.sh"

FORBIDDEN_WORDS = frozenset([
    "eval", "xargs", "awk", "perl", "python", "ruby", "tee", "sed",
    "sort", "uniq", "find", "sudo", "tr", "source", "wget", "curl",
    "nc", "dd",
])
FORBIDDEN_SUBSTR = ("$(", "`", " <(")


def main():
    try:
        data = open(FIX, "rb").read()
    except OSError as e:
        print("FAIL: cannot read %s: %s" % (FIX, e))
        return 1

    text = data.decode("utf-8", "replace")

    # (1) shebang
    first = text.split("\n", 1)[0]
    if first != "#!/usr/bin/env bash":
        print("FAIL: shebang line is %r, want '#!/usr/bin/env bash'" % first)
        return 1

    # (2) line endings
    if b"\r" in data:
        print("FAIL: CR (carriage-return) bytes present - CRLF line endings")
        return 1

    # (3) allowlist / forbidden constructs
    bad = []
    for sub in FORBIDDEN_SUBSTR:
        if sub in text:
            bad.append(sub)
    for word in FORBIDDEN_WORDS:
        if re.search(r"\b" + word + r"\b", text):
            bad.append(word)
    if bad:
        print("FAIL: forbidden construct(s) in fix.sh: %s"
              % ", ".join(sorted(set(bad))))
        return 1

    print("OK: shebang, LF-only, allowlist-sanitized")
    return 0


if __name__ == "__main__":
    sys.exit(main())