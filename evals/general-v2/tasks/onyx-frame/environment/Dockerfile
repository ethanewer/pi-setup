# onyx-frame: boot-splash renderer whose Python source must ship tiny
# (gzip-compressed byte ceiling, no embedded pixel data). Stdlib only.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
