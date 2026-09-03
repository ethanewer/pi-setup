# ds-sash-builder — window-function support for a tiny query builder.
#
# Ships the self-authored `qb` package (core builder + canonical SQL rules)
# and the visible demo script.  The agent must add /app/qb/window.py (the
# OverSpec / window_item extension wired into Qb.select_window) and
# regenerate /app/demo_out.sql; the demo cannot run until the extension
# exists.  Pristine byte copies are kept for tamper detection.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/qb/ /app/qb/
COPY files/demo.py /app/demo.py

# Pristine copies used by the verifier to detect content tampering.
COPY files/qb/ /opt/pristine/qb/
COPY files/demo.py /opt/pristine/demo.py

# Sanity: the shipped core alone is importable and renders canonical SQL
# without the (deliverable) window extension.
RUN python3 -c "from qb import Qb; assert Qb().select('a').from_('t').sql() == 'SELECT \"a\" FROM \"t\"'; print('qb core ok')"