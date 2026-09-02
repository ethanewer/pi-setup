#!/usr/bin/env python3
"""Builds a raw volume image demonstrating a deleted-file carving scenario.

Layout (sector = 512 bytes):
  offset 0     : superblock magic "CASEIMG1\0"
  offset 18    : LE uint64 sector size (512)
  offset 26    : LE uint64 directory table offset
  offset 512   : directory table, two 130-byte records (record 0 = stale decoy,
                 record 1 = live deleted target)
  offset 2048+ : data region

Directory record (130 bytes):
  [0]    status byte (0x10 allocated, 0xE5 deleted)
  [1..4] reserved
  [5]    1-byte name length
  [6..37]name (32 bytes, null-padded)
  [38..45] LE uint64 data offset
  [46..53] LE uint64 size
  rest   reserved
"""
import hashlib
import struct

SECTOR = 512
SIZE = 8192  # 16 sectors

SUPER = bytearray(b"\x00" * 512)
SUPER[0:8] = b"CASEIMG1"
struct.pack_into("<Q", SUPER, 8, SECTOR)
DIR_OFF = 512
struct.pack_into("<Q", SUPER, 16, DIR_OFF)

TARGET_NAME = b"archive/corruption.txt"
DECOY_NAME = b"archive/corruption.txt.old"

TARGET_TEXT = (
    b"Weekly surgical audit of the quarantined instrument set. All three "
    b"actuator families passed the statistical gate after 50 logged runs.\n"
    b"Family B retained a +0.05 mm offset under full load, within tolerance. "
    b"Family C required re-seating the bearing carriage after cycle 3.\n"
    b"Recheck clamping torque before the next acceptance window. -- J.M."
)

# The decoy's original region was reused, so it now contains junk markers.
DECOY_TEXT = b"\xa5\x55\xaa\x2f\xe1" * 200  # length 1000, not equal to target

DATA_OFF = 4 * SECTOR          # 2048
TARGET_OFF = 7 * SECTOR        # 3584
DECOY_OFF = DATA_OFF           # 2048, region re-used with junk

img = bytearray(b"\x00" * SIZE)

decoy_size = 380
img[DECOY_OFF:DECOY_OFF + decoy_size] = b"\x2e" * decoy_size

target_size = len(TARGET_TEXT)
img[TARGET_OFF:TARGET_OFF + target_size] = TARGET_TEXT

def make_record(status, name, offset, size):
    rec = bytearray(130)
    rec[0] = status
    rec[1:5] = b"\x00" * 4
    rec[5] = len(name)
    namelen = min(len(name), 30)
    rec[6:6 + namelen] = name[:namelen]
    struct.pack_into("<QQ", rec, 38, offset, size)
    return bytes(rec)

rec0 = make_record(0xE5, DECOY_NAME, DATA_OFF, decoy_size)
rec1 = make_record(0xE5, TARGET_NAME, TARGET_OFF, target_size)

table = rec0 + rec1
img[DIR_OFF:DIR_OFF + len(table)] = table

img[0:512] = SUPER

out = "/workspace/evidence.dd"
with open(out, "wb") as f:
    f.write(img)

print("wrote %s (%d bytes)" % (out, SIZE))
print("sha256=%s" % hashlib.sha256(img).hexdigest())