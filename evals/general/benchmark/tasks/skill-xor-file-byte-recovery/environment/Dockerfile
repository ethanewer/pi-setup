FROM bench-base:python-3.12

WORKDIR /app

# Create a file whose bytes are a single-byte XOR of a readable plaintext.
RUN python3 - <<'EOF'
plaintext = b"THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"
key = 0x5A
data = bytes(b ^ key for b in plaintext)
with open("/app/data.xor", "wb") as f:
    f.write(data)
EOF