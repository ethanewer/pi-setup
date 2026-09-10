FROM bench-base:python-3.12

# The fixture repository is built at image-build time and is therefore
# root-owned; the trial may run as another uid, so make every repository safe
# for any user and give tag/commit operations a stable identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app

COPY files/ /app/

# Build the visible fixture repository, prove its test suite is green before
# the agent arrives, then drop the generator so only the repository ships.
RUN python3 /app/gen_repo.py visible /app/project \
 && (cd /app/project && PYTHONPATH=src python3 -m unittest discover -s tests -t . >/dev/null) \
 && rm -f /app/gen_repo.py