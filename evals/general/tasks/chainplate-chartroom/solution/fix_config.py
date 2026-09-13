#!/usr/bin/env python3
"""Apply the minimal upstream fix for the chainplate-chartroom bug.

Config.process() resolves {dotted.config.key} templates inside string config
values, substituting the referenced value's string form. The guard was
`if config_value:`, so falsy referenced values (0, False, "") looked unset
and the placeholder was returned literally. The fix substitutes whenever the
referenced key is present (`is not None`) and stringifies the value for
re.sub compatibility.

Usage: fix_config.py /app/src/src/poetry/config/config.py
"""
import sys

BUGGY = """        def resolve_from_config(match: re.Match[str]) -> Any:
            key = match.group(1)
            config_value = self.get(key)
            if config_value:
                return config_value
"""

FIXED = """        def resolve_from_config(match: re.Match[str]) -> str:
            key = match.group(1)
            config_value = self.get(key)
            if config_value is not None:
                return str(config_value)
"""


def main() -> int:
    path = sys.argv[1]
    src = open(path, encoding="utf-8").read()
    if FIXED in src:
        print(f"{path}: already fixed")
        return 0
    if BUGGY not in src:
        raise SystemExit(f"ERROR: expected buggy pattern not found in {path}")
    open(path, "w", encoding="utf-8").write(src.replace(BUGGY, FIXED))
    print(f"{path}: patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())