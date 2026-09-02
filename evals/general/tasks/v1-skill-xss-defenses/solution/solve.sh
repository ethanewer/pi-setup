#!/bin/bash
set -euo pipefail

cat > /app/render.py <<'EOF'
import html

def render_html(user_input):
    return "<div>" + html.escape(user_input, quote=True) + "</div>"
EOF