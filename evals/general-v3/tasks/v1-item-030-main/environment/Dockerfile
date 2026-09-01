FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a git repository riddled with leaked credentials (AWS access key +
# secret + GitHub PAT) across several commits, a branch and an annotated tag.
COPY files/setup_repo.sh /app/setup_repo.sh
RUN bash /app/setup_repo.sh main && rm /app/setup_repo.sh