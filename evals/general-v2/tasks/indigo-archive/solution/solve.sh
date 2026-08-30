#!/bin/bash
# Real oracle for indigo-archive.
# Writes the recovery program /app/recover.py (a genuine implementation of the
# documented volume parser), then RUNS it on /app/volume.bin to produce
# /app/recovered.json and /app/evidence.json. Does the real work; never reads
# /tests and never cats a precomputed answer.
set -eu

cat > /app/recover.py <<'PY'
#!/usr/bin/env python3
"""Recover live records from an indigo-archive volume.

Usage: python3 recover.py <volume_file> <out_recovered.json> <out_evidence.json>

Contract:
  - Header (16 bytes, little-endian): magic b'VOL1', page_size u32,
    table_offset u32, reserved.
  - Record table at table_offset: fixed 32-byte slots.
      u32 magic=0x52454331, u32 status (1 live), u32 payload_offset,
      u32 payload_len, u32 crc32, 12 reserved.
  - A slot is recovered iff magic matches, status==1, payload_len<=4096,
    payload_offset+payload_len<=page_size and <= file length, payload decodes
    as UTF-8, and CRC matches.
  - evidence: image_sha256 = sha256 of the whole volume file; records_sha256 =
    sha256 over the concatenated payload bytes of the recovered records.
"""
import sys, struct, binascii, hashlib, json

VOL_MAGIC = b'VOL1'
REC_MAGIC = 0x52454331
MAX_PAYLOAD = 4096


def recover(data):
    if len(data) < 16 or data[0:4] != VOL_MAGIC:
        return [], 'invalid'
    page_size = struct.unpack_from('<I', data, 4)[0]
    table_off = struct.unpack_from('<I', data, 8)[0]
    if page_size == 0 or table_off + 32 > len(data):
        return [], 'recovered'
    payloads = []
    i = table_off
    while i + 32 <= len(data):
        magic, status, poff, plen, crc = struct.unpack_from('<IIIII', data, i)
        if (magic == REC_MAGIC and status == 1
                and plen <= MAX_PAYLOAD
                and poff + plen <= page_size
                and poff + plen <= len(data)):
            payload = data[poff:poff + plen]
            if (binascii.crc32(payload) & 0xffffffff) == crc:
                try:
                    payload.decode('utf-8')
                except UnicodeDecodeError:
                    pass
                else:
                    payloads.append(payload)
        i += 32
    return payloads, 'recovered'


def main():
    vol_path, rec_path, ev_path = sys.argv[1], sys.argv[2], sys.argv[3]
    data = open(vol_path, 'rb').read()
    payloads, status = recover(data)

    records = [{"id": i + 1, "text": p.decode('utf-8')}
               for i, p in enumerate(payloads)]
    with open(rec_path, 'w', encoding='utf-8') as f:
        json.dump({"records": records, "status": status}, f)

    record_hash = hashlib.sha256(b''.join(payloads)).hexdigest()
    image_hash = hashlib.sha256(data).hexdigest()
    with open(ev_path, 'w', encoding='utf-8') as f:
        json.dump({"image_sha256": image_hash, "records_sha256": record_hash}, f)
    return 0


if __name__ == '__main__':
    sys.exit(main())
PY

chmod +x /app/recover.py

# Run the program on the supplied visible fixture to produce the deliverables.
python3 /app/recover.py /app/volume.bin /app/recovered.json /app/evidence.json
echo "oracle: recovered=$(python3 -c "import json;d=json.load(open('/app/recovered.json'));print(len(d['records']),d['status'])")"