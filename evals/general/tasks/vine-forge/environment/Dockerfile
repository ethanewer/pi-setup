FROM bench-base:python-3.12

# numpy + pandas only (torch is deliberately absent: the scorer ships as .npz
# and streaming inference is numpy work).
RUN pip install --no-cache-dir --disable-pip-version-check numpy pandas

WORKDIR /app

COPY files/ /app/

# Build-time fixtures: the fixed scorer and the visible 8-bag file, generated
# deterministically; the generator is removed so the live container does not
# reveal the exact sampling rule.
RUN python3 /app/gen_fixtures.py \
 && rm -f /app/gen_fixtures.py \
 && rm -rf /app/__pycache__
