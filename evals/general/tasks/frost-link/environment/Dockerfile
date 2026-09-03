FROM bench-base:python-3.12

# frost-link: parametric spacer/flange geometry engine (pure math).
# Ships the visible part spec; a pristine byte copy is kept under /opt so
# the verifier can detect tampering with the fixture.
WORKDIR /app

COPY files/specs/spacer_spec.json /opt/pristine/spacer_spec.json
COPY files/ /app/