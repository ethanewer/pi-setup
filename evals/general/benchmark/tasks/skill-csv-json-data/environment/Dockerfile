FROM bench-base:python-3.12

WORKDIR /app

# Static CSV input with an id column.
RUN cat > /app/data.csv <<'EOF2'
id,name,role,years
1,Ada,Engineer,5
2,Grace,Engineer,8
3,Linus,Mathematician,3
4,Alan,Cryptographer,6
EOF2
