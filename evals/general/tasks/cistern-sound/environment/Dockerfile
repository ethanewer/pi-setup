FROM bench-base:python-3.12

RUN pip install --no-cache-dir pytest==9.1.1

# The repository below is created by a RUN in this file, so it is root-owned,
# and git refuses to operate on a repository owned by another user: it exits
# 128 with "detected dubious ownership". Whether the trial works then depends
# on which user the harness runs it as. Record the exception in /etc/gitconfig
# rather than root's ~/.gitconfig so it holds for every user, and use the
# wildcard because agents also clone into directories of their own.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@paygate.local" \
 && git config --system user.name "paygate build"

WORKDIR /app

# build_repo.sh generates the whole paygate repository (source, spec, fixtures,
# git history) from heredocs, so the fixture is reproducible; it is removed
# from the image afterwards so the agent only ever sees the repository.
COPY files/ /tmp/fixture/
RUN bash /tmp/fixture/build_repo.sh && rm -rf /tmp/fixture

CMD ["/bin/bash"]