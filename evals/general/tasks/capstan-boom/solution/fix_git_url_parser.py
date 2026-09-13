#!/usr/bin/env python3
"""Apply the git URL parsing fix to a semgrep checkout.

semgrep's git URL parser (cli/src/semgrep/external/git_url_parser.py) cannot
turn scp-like git remotes written without an explicit protocol and without a
trailing ".git" into an https URL when the organisation or repository name
contains a dash (e.g. git@code1.somecompany.internal:somecompany-eval/owasp-juice-shop).
None of the parser's regexes can match the full URL, and the fallback regex
then matches only the "user@host:" prefix with an empty pathname, so owner and
name come back None and get_url_from_sstp_url() keeps the raw scp form.

The fix (synced from the upstream resolution of this bug) is in the parser's
regex table:

* the protocol-less regex gains a '(?!\\w+\\://)' negative lookahead so it
  never competes with explicit-protocol URLs, its name group becomes lazy with
  an optional trailing ".git" or "/" so remotes that omit them parse, and the
  protocol regexes' owner/name classes accept '~' and '.'.

This applies the exact same change to whatever checkout it is given, failing
loudly if the expected parent-commit text is not present, and re-checks the
behaviour before exiting 0.
"""

import os
import sys

# The two changed hunks, exactly as they appear in the buggy parent-commit
# source (raw strings: backslashes are literal source text).
HUNK_A_OLD = (
    "r'(?P<pathname>\\/((?P<owner>[\\w\\-%\\/]+)\\/)?'\n"
    "               r'((?P<name>[\\w\\-%\\.]+?)(\\.git|\\/)?)?)$'),"
)
HUNK_A_NEW = (
    "r'(?P<pathname>\\/((?P<owner>[\\w\\-%\\/~\\.]+)\\/)?'\n"
    "               # Matches the last name in a path (non-\"/\").\n"
    "               # Trickily uses lazy matching \"+?\" to remove any\n"
    "               # trailing \".git\" and \"/\" from the end.\n"
    "               r'((?P<name>[\\w\\-%~\\.]+?)(\\.git)?\\/?)?)$'),"
)
HUNK_B_OLD = (
    "re.compile(r'^(?:(?P<user>[^\\n@]+)@)*'\n"
    "               r'(?P<resource>[a-z0-9_.-]*)[:]*'\n"
    "               r'(?P<port>(?<=:)[\\d]+){0,1}'\n"
    "               r'(?P<pathname>\\/?(?P<owner>.+)/(?P<name>.+).git)$'),"
)
HUNK_B_NEW = (
    "re.compile(r'^'\n"
    "               r'(?!\\w+\\://)'\n"
    "               r'(?:(?P<user>[^\\n@]+)@)*'\n"
    "               r'(?P<resource>[a-z0-9_.-]*)[:]*'\n"
    "               r'(?P<port>(?<=:)[\\d]+){0,1}'\n"
    "               r'(?P<pathname>\\/?(?P<owner>.+)/(?P<name>.+?)(\\.git)?\\/?)$'),"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_git_url_parser.py <git_url_parser.py>", file=sys.stderr)
        return 2
    path = sys.argv[1]

    with open(path, encoding="utf-8") as f:
        src = f.read()

    for label, old in (("hunk A (protocol-regex owner/name classes)", HUNK_A_OLD),
                       ("hunk B (protocol-less regex lookahead/lazy name)", HUNK_B_OLD)):
        if src.count(old) != 1:
            print(f"error: expected to find {label} exactly once in {path}, "
                  f"found {src.count(old)}; refusing to patch", file=sys.stderr)
            return 2

    new = src.replace(HUNK_A_OLD, HUNK_A_NEW).replace(HUNK_B_OLD, HUNK_B_NEW)
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)

    # --- behaviour self-check against the edited checkout ----
    # The editable install resolves `semgrep` to the patched tree; import it
    # from a clean cwd so nothing shadows it.
    os.chdir("/")
    from semgrep.meta import get_url_from_sstp_url  # noqa: E402

    checks = [
        (
            "git@code1.somecompany.internal:somecompany-eval/owasp-juice-shop",
            "https://code1.somecompany.internal/somecompany-eval/owasp-juice-shop",
        ),
        (
            "git@host.xz:~user/path/to/repo.git/",
            "https://host.xz/~user/path/to/repo",
        ),
        (
            "https://gitlab.com/example/group2/group3/test-case.git",
            "https://gitlab.com/example/group2/group3/test-case",
        ),
    ]
    for url, expected in checks:
        got = get_url_from_sstp_url(url)
        if got != expected:
            print(f"error: self-check failed for {url!r}: got {got!r}, "
                  f"expected {expected!r}", file=sys.stderr)
            return 1
    print("git_url_parser.py patched; self-check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())