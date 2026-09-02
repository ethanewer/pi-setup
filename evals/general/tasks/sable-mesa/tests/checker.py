#!/usr/bin/env python3
"""Checker for sable-mesa.

Validates the installed dotkit package: root-module exposure of `dot`
(dotkit.dot, `from dotkit import dot`), the dotkit.core.dot kernel, and the
scalar-product contract on the visible case plus every hidden case under
/tests/hidden/<name>/{case.json,expected.json}. Exits 0 only when everything
passes.
"""
import json
import math
import os
import sys

failures = []


def numbers_match(got, want):
    try:
        return math.isclose(float(got), float(want), rel_tol=1e-9, abs_tol=1e-9)
    except (TypeError, ValueError):
        return False


def run_case(name, case, want):
    a_raw, b_raw = case.get("a"), case.get("b")
    if not isinstance(a_raw, list) or not isinstance(b_raw, list):
        return "case '%s': malformed case input" % name
    wrap = case.get("wrap", "list")
    if wrap == "tuple":
        a, b = tuple(a_raw), tuple(b_raw)
    elif wrap == "list":
        a, b = list(a_raw), list(b_raw)
    else:
        return "case '%s': unknown wrap %r" % name

    import dotkit
    import dotkit.core

    if not hasattr(dotkit, "dot") or not callable(dotkit.dot):
        return "dotkit.dot missing or not callable"
    if not hasattr(dotkit.core, "dot") or not callable(dotkit.core.dot):
        return "dotkit.core.dot missing or not callable"
    try:
        from dotkit import dot as named
    except Exception as exc:  # noqa: BLE001
        return "from dotkit import dot failed: %r" % exc
    if not callable(named):
        return "from dotkit import dot is not callable"

    want_kind = want.get("kind")
    outs = {}
    for label, fn in (("root", dotkit.dot), ("named", named), ("core", dotkit.core.dot)):
        try:
            outs[label] = ("value", fn(a, b))
        except ValueError:
            outs[label] = ("error", "ValueError")
        except Exception as exc:  # noqa: BLE001
            return "case '%s': %s call raised %r" % (name, label, exc)

    if want_kind == "error":
        for label, (kind, _) in outs.items():
            if kind != "error":
                return "case '%s': %s call should raise ValueError" % (name, label)
        return None

    if want_kind != "value":
        return "case '%s': malformed expected.json" % name
    expected = want.get("value")
    for label, (kind, got) in outs.items():
        if kind != "value":
            return "case '%s': %s call raised ValueError unexpectedly" % (name, label)
        if not numbers_match(got, expected):
            return "case '%s': %s call got %r want %r" % (name, label, got, expected)
    return None


def main():
    visible_case, visible_expected, hidden_dir = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        with open(visible_case) as f:
            vcase = json.load(f)
        with open(visible_expected) as f:
            vwant = json.load(f)
    except Exception as exc:  # noqa: BLE001
        print("visible fixture unreadable: %r" % exc, file=sys.stderr)
        return 1
    err = run_case("visible", vcase, vwant)
    if err:
        failures.append(err)

    if not os.path.isdir(hidden_dir):
        failures.append("hidden dir missing")
    else:
        for name in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, name)
            cpath, epath = os.path.join(base, "case.json"), os.path.join(base, "expected.json")
            if not (os.path.isfile(cpath) and os.path.isfile(epath)):
                failures.append("hidden '%s': missing case.json/expected.json" % name)
                continue
            try:
                with open(cpath) as f:
                    case = json.load(f)
                with open(epath) as f:
                    want = json.load(f)
            except Exception as exc:  # noqa: BLE001
                failures.append("hidden '%s': fixture unreadable %r" % (name, exc))
                continue
            err = run_case(name, case, want)
            if err:
                failures.append(err)

    for msg in failures:
        print("FAIL: %s" % msg, file=sys.stderr)
    print("checker: %d failure(s)" % len(failures), file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
