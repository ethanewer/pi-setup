#!/usr/bin/env python3
"""Independent decompressor / size checker for the literal/back-ref token format.

Usage:
  python3 _compr_check.py <compressed_file>            # decode; prints P to stdout on
                                                       # byte-exact success (no originals given)
  python3 _compr_check.py <compressed_file> <original_file>   # also require decode == original
Exit 0 only on success.
"""
import struct
import sys


def decompress(stream):
    out = bytearray()
    i = 0
    n = len(stream)
    while i < n:
        flag = stream[i]
        i += 1
        if flag == 0:
            out.append(stream[i])
            i += 1
        else:
            if i + 4 > n:
                raise ValueError('truncated back-reference token')
            ln, dd = struct.unpack_from('<HH', stream, i)
            i += 4
            if ln < 2:
                raise ValueError(f'illegal back-ref length {ln}')
            if dd < 1 or dd > len(out):
                raise ValueError(f'back-reference dist {dd} out of bounds')
            start = len(out) - dd
            for _ in range(ln):
                out.append(out[start])
                start += 1
    return bytes(out)


def main():
    if len(sys.argv) < 2:
        print('usage: _compr_check.py <compressed> [original]')
        return 2
    stream = open(sys.argv[1], 'rb').read()
    payload_size = len(stream)
    try:
        decoded = decompress(stream)
    except Exception as e:  # noqa: BLE001
        print(f'FAIL decode error: {e!r}')
        return 1
    if len(sys.argv) >= 3:
        original = open(sys.argv[2], 'rb').read()
        if decoded != original:
            print(f'FAIL decode mismatch: got {len(decoded)}B expected {len(original)}B')
            return 1
        print(f'P decoded_ok size={payload_size} match_original')
    else:
        print(f'P decoded_ok size={payload_size}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
