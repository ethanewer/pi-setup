#!/usr/bin/env python3
"""Generate a minimal but structurally valid DOOM 1.10 IWAD ('doom1.wad')
plus a timed demo file ('D1.lmp'), entirely from our own authored byte
layout. Nothing here is copied from any upstream WAD.

Usage: genwad.py <outdir> <demotics> [demo_name]
"""
import struct, sys, os

out = sys.argv[1]
demotics = int(sys.argv[2])
demoname = sys.argv[3] if len(sys.argv) > 3 else "D1"

PATCH = (struct.pack("<hhhh", 8, 8, 0, 0)          # width,height,leftoffset,topoffset
          + struct.pack("<8h", *range(24, 32))     # colofs: each an empty (0xff) column
          + b"\xff" * 8)                            # column data: end markers
# 8x8 patch whose columns are all empty -> draws nothing and terminates cleanly
EMPTY = b""

def nm(s, n=8):
    s = s.upper()
    assert len(s) <= n, s
    return s.encode("ascii") + b"\x00" * (n - len(s))

lumps = []  # (name, data)

# sound etc. all empty; we only need structural lumps

lumps.append((nm("PNAMES"), struct.pack("<I", 1) + nm("FLOOR01")))
# P_InitSwitchList hard-requires every episode-1 wall-switch texture at
# startup (shareware uses episode 1). Each entry is a 1-patch texture.
SW1 = ["BRCOM","BRN1","BRN2","BRNGN","BROWN","COMM","COMP","DIRT",
       "EXIT","GRAY","GRAY1","METAL","PIPE","SLAD","STARG",
       "STON1","STON2","STONE","STRTN"]
TEXNAMES = ["SKY1"] + [n for t in SW1 for n in ("SW1" + t, "SW2" + t)]
texdata = b""
texofs = []
o = 4 + 4 * len(TEXNAMES)
for t in TEXNAMES:
    texofs.append(o)
    o += 40
    # maptexture_t (64-bit reader layout): name[8], masked(1)+pad(3),
    # width@12, height@14, columndirectory 8B, patchcount@24, pad,
    # patches[1] = 5 shorts (originx,originy,patch,stepdir,colormap)
    b = bytearray(40)
    b[0:8] = nm(t)
    struct.pack_into("<hh", b, 12, 8, 8)
    struct.pack_into("<h", b, 24, 1)
    struct.pack_into("<hhhhh", b, 28, 0, 0, 0, 0, 0)
    texdata += bytes(b)
lumps.append((nm("TEXTURE1"), struct.pack("<I", len(TEXNAMES))
               + b"".join(struct.pack("<I", v) for v in texofs) + texdata))
lumps.append((nm("COLORMAP"), b"\x00" * 768))
lumps.append((nm("PLAYPAL"), b"\x00" * 768))

lumps.append((nm("F_START"), EMPTY))
lumps.append((nm("FLOOR01"), PATCH))
lumps.append((nm("FLOOR02"), PATCH))
lumps.append((nm("F_SKY1"), PATCH))
lumps.append((nm("F_END"), EMPTY))
lumps.append((nm("S_START"), EMPTY))
lumps.append((nm("S_END"), EMPTY))

# 63 HUD font patches STCFN033..STCFN095
for i in range(33, 96):
    lumps.append((nm("STCFN%03d" % i), PATCH))
# status bar graphics (never drawn)
for i in range(10):
    lumps.append((nm("STTNUM%d" % i), PATCH))
    lumps.append((nm("STYSNUM%d" % i), PATCH))
lumps.append((nm("STTPRCNT"), PATCH))
lumps.append((nm("STTMINUS"), PATCH))
for i in range(6):
    lumps.append((nm("STKEYS%d" % i), PATCH))
lumps.append((nm("STARMS"), PATCH))
for i in range(2, 8):
    lumps.append((nm("STGNUM%d" % i), PATCH))
lumps.append((nm("STFB0"), PATCH))
lumps.append((nm("STBAR"), PATCH))
for i in range(5):
    for j in range(3):
        lumps.append((nm("STFST%d%d" % (i, j)), PATCH))
for i in range(5):
    lumps.append((nm("STFTR%d0" % i), PATCH))
    lumps.append((nm("STFTL%d0" % i), PATCH))
    lumps.append((nm("STFOUCH%d" % i), PATCH))
    lumps.append((nm("STFEVL%d" % i), PATCH))
    lumps.append((nm("STFKILL%d" % i), PATCH))
lumps.append((nm("STFGOD0"), PATCH))
lumps.append((nm("STFDEAD0"), PATCH))

lumps.append((nm("d_e1m1"), EMPTY))  # music lump for E1M1 (fetched at level start)

# map: E1M1 label + 10 consecutive data blocks
# (ML_LABEL=0, ML_THINGS=1 .. ML_BLOCKMAP=10)
# Label lump content is unused.
lumps.append((nm("E1M1"), EMPTY))
# THINGS: one player-1 start at box centre (512,512) mapunits
lumps.append((nm("E1M1T"), struct.pack("<hhhhh", 512, 512, 0, 1, 0)))
# LINEDEFS: 4 walls around the box
lumps.append((nm("E1M1L"),
    struct.pack("<hhhhhhh", 0, 1, 1, 0, 0, 0, 1)
    + struct.pack("<hhhhhhh", 1, 2, 1, 0, 0, 2, 3)
    + struct.pack("<hhhhhhh", 2, 3, 1, 0, 0, 4, 5)
    + struct.pack("<hhhhhhh", 3, 0, 1, 0, 0, 6, 7)))
# SIDEDEFS: 8 sides, all "-" (NoTexture)
side = struct.pack("<hh", 0, 0) + nm("-") + nm("-") + nm("-") + struct.pack("<h", 0)
lumps.append((nm("E1M1S"), side * 8))
# VERTEXES
lumps.append((nm("E1M1V"),
    struct.pack("<hh", 0, 0) + struct.pack("<hh", 1024, 0)
    + struct.pack("<hh", 1024, 1024) + struct.pack("<hh", 0, 1024)))
# SEGS: 4
segs = b"".join(struct.pack("<hhhhhh", a, b, 0, i, 0, 0)
                for i, (a, b) in enumerate([(0, 1), (1, 2), (2, 3), (3, 0)]))
lumps.append((nm("E1M1SEG"), segs))
# SSECTORS: 1
lumps.append((nm("E1M1SS"), struct.pack("<hh", 4, 0)))
# NODES: 1 leaf node pointing at subsector 0
node = struct.pack("<hhhhhhhhhhhhHH", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x8000, 0x8000)
lumps.append((nm("E1M1N"), node))
# SECTORS: 1, floor FLOOR01 ceiling FLOOR02, light 12
lumps.append((nm("E1M1SEC"),
    struct.pack("<hh", 0, 1792) + nm("FLOOR01") + nm("FLOOR02")
    + struct.pack("<hhh", 12, 0, 0)))
# REJECT: empty
lumps.append((nm("E1M1R"), EMPTY))
# BLOCKMAP: 1x1 grid anchored at the player position
lumps.append((nm("E1M1B"), struct.pack("<hhhhh", 512, 512, 1, 1, 5) + struct.pack("<h", 0)))

# ---- assemble WAD ----
def _iter_offsets(ls):
    off = 12 + len(ls) * 16
    for _, d in ls:
        yield (off, len(d))
        off += len(d)

data = b"".join(d for _, d in lumps)
header = b"IWAD" + struct.pack("<II", len(lumps), 12)
entries = []
off = 12 + len(lumps) * 16
for n, d in lumps:
    entries.append(struct.pack("<II", off, len(d)) + n)
    off += len(d)
wad = header + b"".join(entries) + data
with open(os.path.join(out, "doom1.wad"), "wb") as f:
    f.write(wad)

# ---- demo file ----
demo = bytes([110])            # VERSION 110
demo += bytes([2, 1, 1, 0])    # skill medium, ep 1, map 1, deathmatch 0
demo += bytes([0, 0, 0, 0])    # respawn, fast, nomonsters, consoleplayer
demo += bytes([1, 0, 0, 0])    # playeringame[4]
demo += b"\x00" * (4 * demotics)   # one quiet ticcmd per tic
demo += b"\x80"                # DEMOMARKER: end of stream
with open(os.path.join(out, demoname + ".lmp"), "wb") as f:
    f.write(demo)
print("wrote %s/doom1.wad (%d lumps) and %s/%s.lmp (%d tics)"
      % (out, len(lumps), out, demoname, demotics))