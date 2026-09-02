FROM bench-base:python-3.12

WORKDIR /app

# Vulnerable starter: reflects user input without escaping.
RUN cat > /app/render.py <<'EOF'
def render_html(user_input):
    return "<div>" + user_input + "</div>"
EOF