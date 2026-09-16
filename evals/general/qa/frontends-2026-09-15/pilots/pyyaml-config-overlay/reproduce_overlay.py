#!/usr/bin/env python3
import argparse
import sys

sys.path.insert(0, "/app/pyyaml/lib")
import yaml
from yaml.config_overlay import apply_overlay, load_overlay


def main():
    parser = argparse.ArgumentParser(description="apply a safe YAML configuration overlay")
    parser.add_argument("--list-mode", choices=("replace", "append", "unique"), default="replace")
    parser.add_argument("base")
    parser.add_argument("overlay")
    parser.add_argument("output")
    args = parser.parse_args()
    try:
        with open(args.base, encoding="utf-8") as stream:
            base = yaml.safe_load(stream)
        with open(args.overlay, encoding="utf-8") as stream:
            overlay = load_overlay(stream)
        result = apply_overlay(base, overlay, list_mode=args.list_mode)
        with open(args.output, "w", encoding="utf-8") as stream:
            yaml.safe_dump(result, stream, sort_keys=False)
    except (OSError, TypeError, ValueError, yaml.YAMLError) as exc:
        print("reproduce_overlay: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
