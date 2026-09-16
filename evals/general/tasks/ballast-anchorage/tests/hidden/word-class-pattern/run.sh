#!/bin/bash
# Hidden case: same crash path via a different pattern (word-class classes,
# different optional group structure) on the same short-matches haystack.
unset RIPGREP_CONFIG_PATH
exec /app/src/target/debug/rg '(^|[^\w])((\w+)?\s)?b(\s(\w+)?)?($|[^\w])' -U -rx input
