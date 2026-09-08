FROM bench-base:python-3.12

RUN pip install --disable-pip-version-check tzdata==2026.3

WORKDIR /app

COPY files/events.json /app/events.json