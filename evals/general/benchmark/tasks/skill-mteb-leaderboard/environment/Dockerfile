FROM bench-base:python-3.12

WORKDIR /app

# A pseudo-MTEB leaderboard: each model's embedding quality on 3 tasks.
RUN cat > /app/leaderboard.csv <<'EOF'
model,task_a,task_b,task_c
bert-base,50.2,45.6,52.1
sbert-base,58.9,61.3,60.7
e5-small,70.3,72.1,69.5
bge,75.8,77.1,76.4
gpt-large,79.0,80.2,78.5
EOF