FROM bench-base:python-3.12

WORKDIR /app

# Build a small git repo with a dangling commit (subject 'golden-secret').
RUN git init -q /app/repo \
 && git -C /app/repo config user.email 'probe@example.invalid' \
 && git -C /app/repo config user.name 'Probe' \
 && echo 'stable content' > /app/repo/stable.txt \
 && git -C /app/repo add stable.txt \
 && echo 'stable base' | git -C /app/repo commit -q -F - \
 && echo 'recover payload: FLAG-48213' > /app/repo/secret.txt \
 && git -C /app/repo add secret.txt \
 && GIT_AUTHOR_DATE='2020-02-02T00:00:00Z' GIT_COMMITTER_DATE='2020-02-02T00:00:00Z' \
    echo 'golden-secret' | git -C /app/repo commit -q -F - \
 && git -C /app/repo reset --hard HEAD~1