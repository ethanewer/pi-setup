FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/input.txt <<'EOF'
1,2,3,4,5,6,7,8,9,10
EOF

RUN cat > /app/legacy.py <<'PYEOF'
# Originally written for Python 2.
data = open("input.txt").read().strip()
parts = data.split(",")
nums = [int(x) for x in parts]
total = sum(nums)
n = len(nums)
avg = total / n
print "sum=%d count=%d avg=%s" % (total, n, avg)
PYEOF