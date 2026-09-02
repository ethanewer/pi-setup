FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN rm -rf /app/workflow && git init -q -b main /app/workflow && cd /app/workflow && \
    printf '# workflow project\n' > README.md && \
    git add README.md && git -c user.email=b@e.io -c user.name=bench commit -q -m "base" && \
    printf 'def main():\n    print("hello")\n' > app.py && \
    git add app.py && git -c user.email=b@e.io -c user.name=bench commit -q -m "add app.py" && \
    git checkout -q -b feature && \
    printf 'def double(n):\n    return n * 2\n' > util.py && \
    git add util.py && git -c user.email=b@e.io -c user.name=bench commit -q -m "add util module" && \
    printf 'def double(n):\n    return n * 999  # WIP experiment\nJUNK=1\n' > util.py && \
    printf 'x = 1\n' > experiment.py && \
    printf 'junk\n' > junk.txt && \
    git add -A && git -c user.email=b@e.io -c user.name=bench commit -q -m "WIP: experiment" && \
    printf 'from util import double\nassert double(21) == 42\n' > test_util.py && \
    git add test_util.py && git -c user.email=b@e.io -c user.name=bench commit -q -m "add util tests" && \
    git checkout -q main && \
    printf 'TODO refactor\n' >> app.py
