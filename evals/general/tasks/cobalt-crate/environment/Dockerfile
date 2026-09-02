FROM bench-base:python-3.12
WORKDIR /app

# Read-only cratepack store shipped for the agent to unpack.
COPY files/store/ /app/store/
RUN chmod -R a-w /app/store
