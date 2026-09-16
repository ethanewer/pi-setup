FROM bench-base:ubuntu-24.04

WORKDIR /app

COPY files/ /app/

# Build the incident tree deterministically (same generator, same constants as
# the authoring-time catalog), then remove the generator so the fixture cannot
# be re-derived from inside the container.
RUN python3 /app/gen_fixture.py --profile meridian --root /app/data \
    && rm -f /app/gen_fixture.py