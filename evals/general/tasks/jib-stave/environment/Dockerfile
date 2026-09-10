FROM bench-base:node-22

SHELL ["/bin/bash", "-lc"]

# The monorepo below is created by this image's build (root-owned), so record
# the ownership exception for every git user and give builds an identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app

# Fixture generator: writes the jibblin SDK monorepo into /app with a real git
# history, installs dependencies (network available at build time), proves the
# suite green, then lands the deliberate dependency/version skew. The script is
# removed afterwards: the shipped fixture is the repo itself.
COPY files/ /app/
RUN . ~/.nvm/nvm.sh >/dev/null 2>&1; nvm use 22 >/dev/null 2>&1 || true; \
    bash /app/gen_monorepo.sh /app \
    && rm -f /app/gen_monorepo.sh

CMD ["/bin/bash"]