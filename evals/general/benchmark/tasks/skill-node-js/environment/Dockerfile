FROM bench-base:node-22

WORKDIR /app

# Input records for the Node.js data-shaping task.
RUN cat > /app/input.json <<'EOF'
[{"name":"alice","score":10},{"name":"bob","score":30},{"name":"carol","score":20}]
EOF