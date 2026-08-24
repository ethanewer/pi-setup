FROM bench-base:python-3.12

WORKDIR /app

# A SQLite "write-ahead log" (WAL) companion file with a fixed, valid WAL header
# followed by a single 24-byte WAL frame header. Built deterministically with
# struct so the byte offsets are exactly those defined by the SQLite WAL format.
RUN python3 - <<'PY'
import struct

def be(n, nbytes):
    return n.to_bytes(nbytes, 'big')

wal = b''
wal += be(0x377f0682, 4)      # bytes 0-3: WAL magic
wal += be(3007000, 4)         # bytes 4-7: file format version
wal += be(4096, 4)            # bytes 8-11: page size
wal += be(0, 4)               # bytes 12-15: checkpoint sequence number
wal += be(1, 4)               # bytes 16-19: salt-1
wal += be(2, 4)               # bytes 20-23: salt-2
wal += be(0, 4)               # bytes 24-27: checksum-1
wal += be(0, 4)               # bytes 28-31: checksum-2
# First frame header (24 bytes), immediately after the 32-byte header.
wal += be(3, 4)               # bytes 32-35: frame's page number
wal += be(7, 4)               # bytes 36-39: DB size in pages after commit
wal += be(1, 4)               # bytes 40-43: (salt-1 copy)
wal += be(2, 4)               # bytes 44-47: (salt-2 copy)
wal += be(0, 4)               # bytes 48-51: checksum-1
wal += be(0, 4)               # bytes 52-55: checksum-2

with open('/app/data.db-wal', 'wb') as f:
    f.write(wal)
PY