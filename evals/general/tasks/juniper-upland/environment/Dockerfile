FROM bench-base:python-3.12

WORKDIR /app

# Juniper Upland scheduling-desk fixture: the meeting request, per-member
# availability calendars, and the provided per-member roster snapshot producer.
# The availability inputs and the kit helper must remain byte-for-byte intact.
COPY files/ /app/

RUN chmod +x /app/kit/roster_feed.py \
    && chmod -R a+r /app

