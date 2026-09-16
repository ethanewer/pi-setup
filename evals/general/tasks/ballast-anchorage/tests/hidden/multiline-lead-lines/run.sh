#!/bin/bash
# Hidden case: leading non-matching line, then the 8 short matches.
# Panics (exit 101) on the unfixed tree; must print 'xxbxbx' and exit 0 after fix.
unset RIPGREP_CONFIG_PATH
exec /app/src/target/debug/rg '(^|[^a-z])((([a-z]+)?)\s)?b(\s([a-z]+)?)($|[^a-z])' -U -rx input
