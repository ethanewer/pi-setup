FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/lexer_rules.json <<'EOF'
{"rules": [
  {"name": "num",  "pattern": "[0-9]+"},
  {"name": "id",   "pattern": "[A-Za-z_]+"},
  {"name": "lparen", "pattern": "\\("},
  {"name": "rparen", "pattern": "\\)"}
]}
EOF
RUN printf 'abc12xy(a)\n' > /app/input.txt