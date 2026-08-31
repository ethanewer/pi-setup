FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN test -d /app/case/logs && ls /app/case/logs/*.log >/dev/null && echo "case-ok"
