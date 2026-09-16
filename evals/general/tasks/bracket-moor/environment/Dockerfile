FROM bench-base:python-3.12

# The repository at /app/coursebook is authored during the build (root-owned)
# and the agent may run git on it as any harness user; record a system-wide
# safe.directory exception and a committer identity for build-time commits.
RUN git config --system --add safe.directory '*' && \
    git config --system user.email "build@localhost" && \
    git config --system user.name "build"

RUN pip install --no-cache-dir pytest==9.1.1

WORKDIR /app
COPY files/ /app/

RUN bash /app/make_git_history.sh && rm -f /app/make_git_history.sh

# Independent reference copy of the published regression suite, baked into the
# image so the verifier can re-run it against the agent's code without touching
# the repo copy. This is what pins the invariant independent of the agent.
RUN mkdir -p /opt/ref-tests && cp /app/coursebook/tests/test_registrations.py /opt/ref-tests/