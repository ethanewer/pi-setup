FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check icalendar

COPY files/events.ics /app/events.ics