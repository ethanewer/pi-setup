FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PYEOF'
import gzip
payload = b"GREETINGS_FROM_THE_ARCHIVE: 92817"
open('/app/archive.bin', 'wb').write(gzip.compress(payload))
PYEOF