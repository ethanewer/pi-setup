FROM bench-base:python-3.12

# rust-orchid: category-partition test-frame generation.
# Ships the visible TSL specification (grammar documented in its header) and
# the frame-generation parameters; the agent writes the generator CLI.
WORKDIR /app

COPY files/ /app/

RUN chmod -R a+r /app && find /app -type d -exec chmod a+rx {} \;