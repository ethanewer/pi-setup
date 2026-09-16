#!/bin/bash
# dragger-narrows reproduction: whitespace-padded entries in a Python
# version file are silently dropped by `uv python pin`.
#
# Usage: UV_BIN=/path/to/uv [bash /app/repro.sh]
# Prints uv's stdout/stderr unchanged and exits with uv's exit status.
# Broken behaviour (pre-fix): empty stdout, one "Ignoring unsupported Python
# request" warning per padded entry. Fixed behaviour: prints 3.12 and 3.10.
set -u

UV_BIN="${UV_BIN:-/app/src/target/debug/uv}"
[ -x "$UV_BIN" ] || { echo "no uv binary at $UV_BIN" >&2; exit 3; }

WORK="$(mktemp -d)" || exit 4
trap 'rm -rf "$WORK"' EXIT

printf '  python3.12  \n \t\n  # 3.11\n\tpython3.10\t\n' > "$WORK/.python-version"

cd "$WORK" || exit 5
HOME="$WORK" "$UV_BIN" python pin