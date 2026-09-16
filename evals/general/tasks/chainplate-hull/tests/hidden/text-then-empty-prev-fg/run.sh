#!/bin/bash
# Hidden CLI case: reaches the empty-textgroup / prev_fg-prev_bg code path in
# src/formatter/string_formatter.rs from a format string the upstream tests
# do not use. Output is byte-compared by /tests/test.sh against `expected`.
export STARSHIP_CONFIG="$PWD/input"
exec /app/src/target/debug/starship prompt
