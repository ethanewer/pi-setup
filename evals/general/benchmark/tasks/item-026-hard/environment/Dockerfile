FROM bench-base:python-3.12

WORKDIR /app

RUN pip install -q --break-system-packages bottle pytest

# The vulnerable service project (a git repository at /app).
COPY files/service/ /app/service/
COPY files/tests/ /app/tests/
COPY files/README.md /app/README.md

RUN git config --global user.email "dev@bench.test" && \
    git config --global user.name "Dev" && \
    git config --global init.defaultBranch main && \
    cd /app && \
    git init >/dev/null 2>&1 && \
    git add -A && \
    git commit -q -m "base: session issuance service (carries CWE-93 header injection)"

WORKDIR /app