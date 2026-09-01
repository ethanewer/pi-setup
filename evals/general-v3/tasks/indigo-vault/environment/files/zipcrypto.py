"""Deterministic ZipCrypto (legacy PKZIP) encrypted-zip writer.

Used at image build time to mint the visible fixture archive and, with
fresh arguments, by the verifier to mint hidden fixture archives.
"""
import struct
import zlib


def data_crc(data):
    """CRC32 as stored in zip headers (zlib convention, complemented)."""
    return zlib.crc32(data) & 0xFFFFFFFF


def _gen_crc(crc):
    for _ in range(8):
        if crc & 1:
            crc = (crc >> 1) ^ 0xEDB88320
        else:
            crc >>= 1
    return crc


_TABLE = None


def _table():
    global _TABLE
    if _TABLE is None:
        _TABLE = [_gen_crc(i) for i in range(256)]
    return _TABLE


def _crc_byte(ch, crc):
    return (crc >> 8) ^ _table()[(crc ^ ch) & 0xFF]


class ZipCrypto:
    """Legacy PKZIP stream cipher (as implemented by zipfile's decrypter)."""

    def __init__(self, pwd):
        self.k0, self.k1, self.k2 = 0x12345678, 0x23456789, 0x34567890
        for b in pwd:
            self._update(b)

    def _update(self, c):
        self.k0 = _crc_byte(c, self.k0)
        self.k1 = (self.k1 + (self.k0 & 0xFF)) & 0xFFFFFFFF
        self.k1 = (self.k1 * 134775813 + 1) & 0xFFFFFFFF
        self.k2 = _crc_byte(self.k1 >> 24, self.k2)

    def _stream(self):
        k = self.k2 | 2
        return ((k * (k ^ 1)) >> 8) & 0xFF

    def encrypt(self, data, crc):
        # 12-byte encryption header: 11 deterministic pseudo-random bytes
        # followed by the high byte of the CRC32.
        hdr = bytes(((i * 73 + 11) & 0xFF) for i in range(11))
        hdr += bytes([(crc >> 24) & 0xFF])
        out = bytearray()
        for b in hdr + data:
            out.append(b ^ self._stream())
            self._update(b)
        return bytes(out)


def write_encrypted_zip(path, password, members):
    """Write a stored-method, ZipCrypto-encrypted zip.

    members: list of (name: str, data: bytes).
    """
    password = password.encode() if isinstance(password, str) else password
    centrals = []
    offset = 0
    with open(path, "wb") as fh:
        for name, data in members:
            nb = name.encode()
            crc = data_crc(data)
            enc = ZipCrypto(password).encrypt(data, crc)
            csize = len(enc)
            local = struct.pack(
                "<IHHHHHIIIHH", 0x04034B50, 20, 0x0001, 0, 0x4800, 0x5A22,
                crc, csize, len(data), len(nb), 0,
            ) + nb + enc
            fh.write(local)
            centrals.append(struct.pack(
                "<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0x0001, 0,
                0x4800, 0x5A22, crc, csize, len(data), len(nb),
                0, 0, 0, 0, 0, offset,
            ) + nb)
            offset += len(local)
        cd_start = offset
        cd = b"".join(centrals)
        fh.write(cd)
        fh.write(struct.pack(
            "<IHHHHIIH", 0x06054B50, 0, 0, len(members), len(members),
            len(cd), cd_start, 0,
        ))


if __name__ == "__main__":
    # Self-test: mint an archive and read it back with zipfile.
    import io
    import zipfile

    buf_path = "/tmp/_zc_selftest.zip"
    payload = b"self test\nalpha=1\nbeta=ok\n"
    write_encrypted_zip(buf_path, "hunter2", [("note.txt", payload)])
    zf = zipfile.ZipFile(buf_path)
    assert zf.namelist() == ["note.txt"]
    assert zf.read("note.txt", pwd=b"hunter2") == payload
    try:
        zf.read("note.txt", pwd=b"wrongpw")
        raise AssertionError("wrong password accepted")
    except RuntimeError:
        pass
    print("zipcrypto self-test OK")
