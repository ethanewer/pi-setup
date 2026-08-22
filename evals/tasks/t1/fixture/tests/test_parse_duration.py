import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from parse_duration import parse_duration  # noqa: E402

VALID = [("90", 90), ("45s", 45), ("2m", 120), ("1h30m", 5400), ("1h", 3600), ("0", 0)]
INVALID = ["", "abc", "1x", "h", "1h30", " 1h", "-5s", "1..5s", "m30", "1h-30m"]


def run():
    failures = []
    for text, want in VALID:
        try:
            got = parse_duration(text)
            if got != want:
                failures.append(f"parse_duration({text!r}) = {got}, want {want}")
        except Exception as e:  # noqa: BLE001
            failures.append(f"parse_duration({text!r}) raised {e!r}, want {want}")
    for text in INVALID:
        try:
            got = parse_duration(text)
            failures.append(f"parse_duration({text!r}) = {got}, want ValueError")
        except ValueError:
            pass
        except Exception as e:  # noqa: BLE001
            failures.append(f"parse_duration({text!r}) raised {type(e).__name__}, want ValueError")
    if failures:
        print("FAIL")
        for f in failures:
            print(" -", f)
        sys.exit(1)
    print("PASS: all duration validation tests passed")


if __name__ == "__main__":
    run()
