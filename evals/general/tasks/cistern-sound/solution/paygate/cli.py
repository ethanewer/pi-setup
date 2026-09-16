"""CLI for rendering settlement reports: python3 -m paygate LEDGER OUT."""
import json
import sys

from . import report


def main(argv=None):
    args = list(sys.argv[1:]) if argv is None else list(argv)
    if len(args) != 2:
        print("usage: python3 -m paygate LEDGER.json OUT.json", file=sys.stderr)
        return 2
    try:
        period, groups = report.load_ledger(args[0])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print("malformed ledger: %s" % exc, file=sys.stderr)
        return 1
    out = report.build_report(period, groups)
    with open(args[1], "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
