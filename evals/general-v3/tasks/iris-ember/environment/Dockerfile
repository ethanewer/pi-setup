FROM bench-base:python-3.12

WORKDIR /app

# Calendar/datetime/tabular helpers used by the task's ICS handling and
# (optionally) by an agent's scheduler. python-dateutil is used by the
# independent verifier to parse DTSTART/DTEND; ics provides a standards
# calendar parser; pandas is available for convenience.
RUN pip install --no-cache-dir \
        ics \
        python-dateutil \
        pandas

# Provided fixtures: attendee availability minutes and the per-person schedule
# producer tool that the deliverable must discover and drive.
COPY files/ /app/

# No binary fixtures beyond the text/JSON nightly above; the agent authors the
# deliverable program itself and this COPY keeps the fixture payload.