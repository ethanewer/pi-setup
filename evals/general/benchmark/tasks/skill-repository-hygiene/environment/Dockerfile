FROM bench-base:python-3.12

WORKDIR /app

RUN mkdir -p /app/repo/cache /app/repo/__pycache__ \
 && printf 'print("hi")\n' > /app/repo/main.py \
 && printf '# harbor readme\n' > /app/repo/README.md \
 && printf 'debug output line\n' > /app/repo/debug.log \
 && printf 'temporary junk\n' > /app/repo/temp.tmp \
 && printf 'cache payload\n' > /app/repo/cache/output.dat \
 && printf 'compiled bytecode\n' > /app/repo/__pycache__/m.pyc \
 && git init -q /app/repo \
 && git -C /app/repo config user.email 'probe@example.invalid' \
 && git -C /app/repo config user.name 'Probe'