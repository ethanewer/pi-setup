# tl-ember-tangle — diagnose and repair a race condition in a concurrent
# async service.
#
# Ships a buggy asyncio word-count aggregation service (/app/svc/
# wordcount_service.py), a deterministic load generator (/app/svc/loadgen.py)
# and a corpus (/app/data/corpus.txt).  Byte-identical pristine copies are
# kept at /opt/pristine/ for the verifier: it re-runs the ORIGINAL service to
# prove the bug reproduces, and runs the load generator unmodified.

FROM bench-base:python-3.12

WORKDIR /app

COPY svc/ /app/svc/
COPY data/ /app/data/

# Pristine reference copies the verifier uses to prove the seeded bug
# reproduces and to keep the load generator unmodified.
COPY svc/wordcount_service.py /opt/pristine/wordcount_service.py
COPY svc/loadgen.py           /opt/pristine/loadgen.py
COPY data/corpus.txt          /opt/pristine/corpus.txt

RUN chmod 0755 /app/svc/loadgen.py /app/svc/wordcount_service.py \
               /opt/pristine/loadgen.py /opt/pristine/wordcount_service.py \
    && python3 -c "import ast,sys; [ast.parse(open(p).read()) for p in ['/app/svc/loadgen.py','/app/svc/wordcount_service.py']]; print('fixture syntax OK')"