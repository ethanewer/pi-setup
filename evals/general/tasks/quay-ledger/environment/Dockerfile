FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq sqlite3 >/dev/null 2>&1

WORKDIR /app

COPY files/ /app/
