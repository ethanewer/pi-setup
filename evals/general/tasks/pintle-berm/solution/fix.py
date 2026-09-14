#!/usr/bin/env python3
"""Oracle fix for pintle-berm.

Applies the same change as upstream rust-lang/regex 73f7889 to the checkout
given as argv[1]:

1. In regex-automata/src/meta/limited.rs, in both reverse search routines
   (`dfa_try_search_half_rev` and `hybrid_try_search_half_rev`), record
   whether the DFA was dead BEFORE the end-of-input transition, and after the
   transition bail out with a Quadratic retry error when the search reached
   the start of its span yet the found match starts past that start while the
   FSM could still have kept matching — i.e. when the optimization cannot
   prove the reported match is the leftmost one. The slower, correct meta
   search then takes over and produces the true leftmost match.

2. Appends a regression case encoding the CORRECT expected behaviour (leftmost
   match, exact byte offsets and captures) to testdata/regression.toml.

The patch is applied with exact-string anchors that must each match exactly
once, so the script fails closed if the checkout drifts from the pinned
commit. Only those two paths are touched.
"""

import subprocess
import sys

SRC = sys.argv[1]
LIMITED = f"{SRC}/regex-automata/src/meta/limited.rs"
TESTDATA = f"{SRC}/testdata/regression.toml"

TRIP_WIRE = """    if at == input.start()
        && mat.map_or(false, |m| m.offset() > input.start())
        && !was_dead
    {
        trace!(
            "reached beginning of search at offset {} without hitting \\
             a dead state, quitting to avoid potential false positive match",
            at,
        );
        return Err(RetryError::Quadratic(RetryQuadraticError::new()));
    }
"""

REPLACEMENTS = [
    # dfa_try_search_half_rev (full DFA build)
    (
        "    dfa_eoi_rev(dfa, input, &mut sid, &mut mat)?;\n    Ok(mat)\n}",
        "    let was_dead = dfa.is_dead_state(sid);\n"
        "    dfa_eoi_rev(dfa, input, &mut sid, &mut mat)?;\n"
        + TRIP_WIRE
        + "    Ok(mat)\n}",
    ),
    # hybrid_try_search_half_rev (lazy hybrid DFA)
    (
        "    hybrid_eoi_rev(dfa, cache, input, &mut sid, &mut mat)?;\n    Ok(mat)\n}",
        "    let was_dead = sid.is_dead();\n"
        "    hybrid_eoi_rev(dfa, cache, input, &mut sid, &mut mat)?;\n"
        + TRIP_WIRE
        + "    Ok(mat)\n}",
    ),
]

REPRO_ENTRY = """# Oracle reproduction: optional-prefix leftmost-match bug. The leftmost
# match on this haystack starts at 0 (the optional group consumes '102:');
# the buggy reverse inner optimization reports 1..9.
[[test]]
name = "oracle-reverse-inner-repro"
regex = '(?:(\\d+)[:.])?(\\d{1,2})[:.](\\d{2})'
haystack = '102:12:39'
matches = [[[0, 9], [0, 3], [4, 6], [7, 9]]]
"""


def patch_file(path, replacements):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    for old, new in replacements:
        if text.count(old) != 1:
            raise SystemExit(f"anchor not found exactly once: {old!r}")
        text = text.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    patch_file(LIMITED, REPLACEMENTS)
    with open(TESTDATA, "r", encoding="utf-8") as f:
        data = f.read()
    if "oracle-reverse-inner-repro" not in data:
        if not data.endswith("\n"):
            data += "\n"
        data += REPRO_ENTRY
        with open(TESTDATA, "w", encoding="utf-8") as f:
            f.write(data)
    # sanity: repository status shows only the two allowed paths
    status = subprocess.run(
        ["git", "-C", SRC, "status", "--porcelain"],
        capture_output=True, check=True, text=True).stdout
    for line in status.splitlines():
        entry = line[:3] + line[3:].split(" ")[0] if len(line) > 3 else line
        if entry not in (" M regex-automata/src/meta/limited.rs", " M testdata/regression.toml"):
            raise SystemExit(f"unexpected working-tree changes:\n{status}")
    print("limited.rs patched; regression case appended")


if __name__ == "__main__":
    main()