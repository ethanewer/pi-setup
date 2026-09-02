# crane-anvil — Torrigan snow-survey build environment.
# gfortran toolchain; locked Fortran sources + station data are baked into /app.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gfortran make && \
    rm -rf /var/lib/apt/lists/*

COPY files/ /app/

RUN chmod -R a+rX /app

WORKDIR /app
