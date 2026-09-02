#!/usr/bin/env python3
"""Decode the custom 'KMSH' skinned-mesh binary into a NumPy .npz archive.
Usage: decode_mesh.py <input.bin> <output.npz>

Binary layout (little-endian):
  0..4   magic 'KMSH'
  4..8   version uint32 (must == 3)
  8..12  vertex count V uint32
  12..16 bone count B uint32
  16..   vertices, V records of 44 bytes each:
            pos     3 x float32   (bytes 0:12)
            normal  3 x float32   (bytes 12:24)
            texcoord2 x float32   (bytes 24:32)
            weights 4 x uint8     (bytes 32:36)  quantized 0..255
            bones   4 x uint16    (bytes 36:44)  bone indices
         then skeleton, B records of 30 bytes each:
            parent   int16        (bytes 0:2)  root == -1
            bindpos  3 x float32  (bytes 2:14)
            quat     4 x float32  (bytes 14:30)  w,x,y,z

Emitted .npz keys (exact):
   positions (V,3) f32, normals (V,3) f32, texcoords (V,2) f32,
   weights (V,4) u8, bones (V,4) u16, parents (B,) i16, bind_pose (B,7) f32.

Malformed input (bad magic, version!=3, or truncated) exits non-zero.
"""
import numpy as np
import sys

KEYS = ["positions", "normals", "texcoords", "weights", "bones", "parents", "bind_pose"]


def decode(path):
    raw = open(path, "rb").read()
    if len(raw) < 16 or raw[:4] != b"KMSH":
        raise ValueError("bad magic")
    ver = int(np.frombuffer(raw[4:8], dtype="<u4")[0])
    if ver != 3:
        raise ValueError("unsupported version %d" % ver)
    V = int(np.frombuffer(raw[8:12], dtype="<u4")[0])
    B = int(np.frombuffer(raw[12:16], dtype="<u4")[0])
    need = 16 + V * 44 + B * 30
    if len(raw) < need:
        raise ValueError("truncated input (%d bytes, need %d)" % (len(raw), need))

    v = np.frombuffer(raw[16:16 + V * 44], dtype=np.uint8).reshape(V, 44)
    positions = v[:, 0:12].copy().view("<f4").reshape(V, 3)
    normals = v[:, 12:24].copy().view("<f4").reshape(V, 3)
    texcoords = v[:, 24:32].copy().view("<f4").reshape(V, 2)
    weights = v[:, 32:36].copy()
    bones = v[:, 36:44].copy().view("<u2").reshape(V, 4)

    sk = np.frombuffer(raw[16 + V * 44:16 + V * 44 + B * 30], dtype=np.uint8).reshape(B, 30)
    parents = sk[:, 0:2].copy().view("<i2").reshape(B)
    bind_pose = np.concatenate([
        sk[:, 2:14].copy().view("<f4").reshape(B, 3),
        sk[:, 14:30].copy().view("<f4").reshape(B, 4),
    ], axis=1)
    return {"positions": positions, "normals": normals, "texcoords": texcoords,
            "weights": weights, "bones": bones, "parents": parents, "bind_pose": bind_pose}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: decode_mesh.py <input.bin> <output.npz>\n")
        sys.exit(2)
    try:
        data = decode(sys.argv[1])
    except ValueError as e:
        sys.stderr.write("decode error: %s\n" % e)
        sys.exit(1)
    np.savez(sys.argv[2], **data)
    print("decoded vertices=%d bones=%d" % (data["positions"].shape[0], data["parents"].shape[0]))
