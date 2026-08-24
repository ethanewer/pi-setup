FROM bench-base:python-3.12

WORKDIR /app

# Build a deterministic FAT16 floppy disk image (2880 x 512 sectors).
RUN python3 - <<'PY'
import struct
SECTORS = 2880
img = bytearray(SECTORS * 512)
# jump instruction + OEM name
img[0:3] = b'\xeb\x3c\x90'
img[3:11] = b'MSWIN4.1'
struct.pack_into('<H', img, 11, 512)          # bytes per sector
img[13] = 1                                    # sectors per cluster
struct.pack_into('<H', img, 14, 1)             # reserved sectors
img[16] = 2                                    # number of FATs
struct.pack_into('<H', img, 17, 224)           # root directory entries
struct.pack_into('<H', img, 19, SECTORS)       # total sectors
struct.pack_into('<H', img, 22, 9)             # sectors per FAT
# volume label at offset 43, 11 bytes
img[43:54] = b'DISKIMG26'.ljust(11, b'\x00')
open('/app/floppy.img', 'wb').write(bytes(img))
PY