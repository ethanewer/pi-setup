FROM bench-base:node-22

# The fixture repository is generated at image build time (staged git history),
# so git must trust any user the trial runs as and have a committer identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

# 1. assemble the repository with its full git history (HEAD = the regression
#    commit the agent must fix),
# 2. install the pinned toolchain from the committed lockfile (offline at trial),
# 3. prove the shipped shape: suite red on the broken components, build green
#    but emitting neither ESM nor declarations,
# 4. drop the generator, open the tree for whoever the trial runs as.
RUN bash /app/gen/assemble.sh \
 && npm install --no-audit --no-fund \
 && bash /app/gen/selfcheck.sh \
 && rm -rf /app/gen \
 && chmod -R a+rwX /app
