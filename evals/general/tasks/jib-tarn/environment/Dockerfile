FROM bench-base:python-3.12

RUN pip install --no-cache-dir pytest==9.1.1

# The repository is root-owned (built at image build time); make it safe for
# every user the harnesses may run as, and give builds a committer identity so
# build-time and trial-time commits work.
RUN git config --system --add safe.directory '*' && \
    git config --system user.email "build@localhost" && \
    git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

# Build the 25-commit sundial repository. The generator script is part of the
# fixture deliverable; remove it once the repository exists.
RUN bash /app/make_repo.sh && rm -f /app/make_repo.sh && chmod -R a+rwX /app

# The correctness suite must be green before any agent arrives.  The fixture's
# own tests pass even though the hot path at HEAD is unintentionally O(n^2).
RUN cd /app/repo && python3 -m pytest -q