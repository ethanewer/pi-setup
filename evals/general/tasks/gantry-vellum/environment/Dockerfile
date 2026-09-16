FROM bench-base:python-3.12

# The checkout built inside this image carries a git history; make it usable
# by whatever uid the trial runs under and give the build-time commits an
# identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

# Generate the service checkout from the committed generator (reproducible
# fixture), create the visible workload, and build the git history.  The
# driver script is consumed here so /app carries only the fixture tooling
# plus the repository itself.
RUN bash /app/tools/build_repo.sh && rm -f /app/tools/build_repo.sh

# The shipped checkout must be green before any agent arrives.
RUN cd /app/enrichd && python3 -m unittest discover -s tests -t . -q