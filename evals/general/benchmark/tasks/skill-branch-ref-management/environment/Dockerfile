FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN rm -rf /app/work /app/src.git && \
    git init -q --bare /app/src.git && \
    git init -q -b main /app/work && \
    cd /app/work && \
    printf '# refs demo\n' > README.md && \
    git add README.md && git -c user.email=b@e.io -c user.name=bench commit -q -m "init repo" && \
    mkdir -p lib && \
    printf 'def feature():\n    return 42\n' > lib/x.py && \
    git add lib/x.py && git -c user.email=b@e.io -c user.name=bench commit -q -m "add feature X" && \
    printf 'wiring fix\n' > wiring.txt && \
    git add wiring.txt && git -c user.email=b@e.io -c user.name=bench commit -q -m "fix main wiring" && \
    git remote add origin /app/src.git && \
    git push -q origin main
