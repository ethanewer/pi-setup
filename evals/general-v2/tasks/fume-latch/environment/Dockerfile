# fume-latch — repair-desk runtime.
#
# Ships the deterministic HTTP fix desk, the visible defective plate file, the
# per-line work order and the visible session descriptor. The verifier starts
# fresh desk sessions for hidden cases, so the deliverable client must be
# generic.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN chmod 644 /app/desk_service.py /app/plate.txt /app/work_order.json \
              /app/desk/visible_case.json
