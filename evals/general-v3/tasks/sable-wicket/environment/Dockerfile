FROM bench-base:python-3.12

WORKDIR /app

# The defective library, the audit report, and the patchdeck applier.
COPY files/ /app/

RUN chmod +x /app/tools/patchdeck.py /app/selfcheck.py
