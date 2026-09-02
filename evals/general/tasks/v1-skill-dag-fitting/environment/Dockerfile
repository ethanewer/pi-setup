FROM bench-base:python-3.12

WORKDIR /app

# A directed acyclic graph (DAG): each line is "u v" meaning a directed edge u -> v.
RUN cat > /app/edges.txt <<'EOF'
1 2
1 3
2 4
3 4
3 5
4 5
5 6
EOF