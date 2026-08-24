FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build a git repository riddled with leaked credentials (AWS key id/secret,
# GitHub PAT, GitHub fine-grained token) across commits, commit MESSAGES,
# a branch, a legacy branch and an annotated tag, with all objects packed.
COPY files/setup_repo.sh /app/setup_repo.sh
RUN bash /app/setup_repo.sh hard && rm /app/setup_repo.sh