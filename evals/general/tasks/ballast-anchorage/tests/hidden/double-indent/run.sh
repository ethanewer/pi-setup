#!/bin/bash
# Hidden case: two leading spaces shift every match offset; the over-range
# tail slice must still be clamped. Must print 'xbxbx' and exit 0 after fix.
unset RIPGREP_CONFIG_PATH
exec /app/src/target/debug/rg '(^|[^a-z])((([a-z]+)?)\s)?b(\s([a-z]+)?)($|[^a-z])' -U -rx input
