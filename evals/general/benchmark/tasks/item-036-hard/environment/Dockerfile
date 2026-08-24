FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y vim \
    && rm -rf /var/lib/apt/lists/*

# Generate a 1,000,000-row CSV: a header plus `<id>,<two-letter code>` rows.
# The code is deterministic from the row id, so the verifier can recompute the
# expected transform independently by reading data.csv.
RUN python3 - <<'PY'
W = 1_000_000
with open('/app/data.csv', 'w', newline='') as f:
    f.write('id,code\n')
    for i in range(1, W + 1):
        code = chr(ord('A') + (i // 26) % 26) + chr(ord('A') + i % 26)
        f.write('%d,%s\n' % (i, code))
print('wrote', W, 'rows')
PY