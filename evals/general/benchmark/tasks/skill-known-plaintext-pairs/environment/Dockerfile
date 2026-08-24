FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/known_plain.txt <<'EOF'
HELLOWORLD
EOF

RUN cat > /app/known_cipher.txt <<'EOF'
KHOORZRUOG
EOF

RUN cat > /app/ciphertext.txt <<'EOF'
DWWDFNWGDZQ
EOF