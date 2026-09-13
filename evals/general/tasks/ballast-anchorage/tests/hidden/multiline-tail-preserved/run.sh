#!/bin/bash
# Hidden case: an 8-short-match line followed by more content that must be
# PRESERVED in the multiline replacement output. A fix that merely clamps the
# last-match position to the range end drops the trailing 'dd' line (wrong);
# the correct fix keeps it. Panics (exit 101) on the unfixed tree.
unset RIPGREP_CONFIG_PATH
exec /app/src/target/debug/rg '(^|[^a-z])((([a-z]+)?)\s)?b(\s([a-z]+)?)($|[^a-z])' -U -rx input
