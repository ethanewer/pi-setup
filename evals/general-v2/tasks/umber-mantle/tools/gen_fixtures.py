#!/usr/bin/env python3
"""Generate input fixture trees for the umber-mantle benchmark task.

Dev tool, run once. Produces:
  environment/files/            -> visible /app fixtures
  tests/hidden/H1..H3/          -> three hidden scenario input trees

The verifier recomputes expected outputs independently from the fixture inputs,
so fixtures are only inputs and never encode the answer directly.
"""
import os, io, gzip, tarfile, struct, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
TASK = os.path.dirname(HERE)
ENVFILES = os.path.join(TASK, "environment", "files")
HIDDEN = os.path.join(TASK, "tests", "hidden")


# ---------------------------------------------------------------------------
# Small legit x86-64 statically-typed ELF that just calls exit(code).
# bytes are deterministic and identical on every host (no compiler needed).
def build_elf(exit_code: int) -> bytes:
    code = bytes([0xBF, exit_code & 0xFF, 0, 0, 0,   # mov edi, exit_code
                  0xB8, 60, 0, 0, 0,                # mov eax, 60 (SYS_exit)
                  0x0F, 0x05])                      # syscall
    ehsize, phentsize, phoff = 64, 56, 64
    code_off = phoff + phentsize          # 120
    filesz = code_off + len(code)
    vbase = 0x400000
    ident = b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\x00" * 8
    ehdr = bytearray(64)
    ehdr[0:16] = ident
    struct.pack_into("<HHI", ehdr, 16, 2, 62, 1)          # type, machine, version
    struct.pack_into("<Q", ehdr, 24, vbase + code_off)    # e_entry
    struct.pack_into("<Q", ehdr, 32, phoff)               # e_phoff
    struct.pack_into("<Q", ehdr, 40, 0)                   # e_shoff
    struct.pack_into("<I", ehdr, 48, 0)                   # e_flags
    struct.pack_into("<HHHHHH", ehdr, 52, ehsize, phentsize, 1, 0, 0, 0)
    phdr = struct.pack("<IIQQQQQQ",
       1,          # PT_LOAD
       5,          # p_flags R|X
       0,          # p_offset
       vbase,      # p_vaddr
       vbase,      # p_paddr
       filesz,     # p_filesz
       filesz,     # p_memsz
       0x1000)     # p_align
    return bytes(ehdr) + phdr + code


def hexdump_xxd(data: bytes, width: int = 16) -> bytes:
    """xxd-style hex dump: offset column, 16 two-digit hex bytes, ascii column.

    Non-printable AND space bytes render as '.' in the ascii column so the
    annotation never introduces whitespace tokens -- keeps reassembly from the
    hex groups unambiguous.
    """
    lines = []
    for off in range(0, len(data), width):
        chunk = data[off:off + width]
        hexpart = " ".join(f"{b:02x}" for b in chunk)
        ascpart = "".join(chr(b) if 33 <= b <= 126 else "." for b in chunk)
        lines.append(f"{off:08x}  {hexpart}  {ascpart}")
    return ("\n".join(lines) + "\n").encode()


def gzip_bytes(data: bytes) -> bytes:
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as f:
        f.write(data)
    return buf.getvalue()


def write(path, data, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(data, str):
        data = data.encode()
    with open(path, "wb") as f:
        f.write(data)
    if mode is not None:
        os.chmod(path, mode)


def build_tree(dest, variant, gzip_printer, with_cache=True):
    """Build one input tree under dest. Recorded originals are returned."""
    os.makedirs(dest, exist_ok=True)
    d = os.path.join(dest, "data")

    main = (
        "batch,order,skucount,amount\n"
        f"A-00{variant},q-{variant}-901,3,42.50\n"
        f"A-00{variant},q-{variant}-902,7,118.25\n"
        f"A-00{variant},q-{variant}-903,2,19.00\n"
    ).encode()
    write(os.path.join(d, "records", "main.csv"), main)
    write(os.path.join(d, "records", "other.csv"),
          f"trace,alert,level\nt{variant},warn,2\nt{variant},clean,0\n".encode())
    write(os.path.join(d, "aux", "index.txt"),
          f"index volume {variant}\n" + "x" * 40 + "\n")

    example = (
        "#!/usr/bin/env python3\n"
        "# example ETL probe -- DO NOT MODIFY\n"
        "def probe(data: bytes) -> int:\n"
        "    return sum(b for b in data) & 0xFF\n"
        f"if __name__ == '__main__':\n"
        f"    print(f'probe-{variant}-{{probe(b\"xy\")}}') \n"
    ).encode()
    write(os.path.join(d, "scripts", "etl_probe.py"), example)
    write(os.path.join(d, "scripts", "seed.py"),
          f"# seed runner v{variant}\nprint('seed')\n".encode())

    # strokes that the archiver must EXCLUDE
    if with_cache:
        write(os.path.join(d, "scripts", "__pycache__",
                           "etl_probe.cpython-312.pyc"), bytes([0] * 128))
    write(os.path.join(d, "third_party", "kittor", "lib", "kit.py"),
          b"# vendored dep payload\n")
    write(os.path.join(d, "third_party", "kittor", "METADATA"),
          b"name: kittor\nbuild-cache: no\n")
    write(os.path.join(d, "local", "build", "syms.o"),
          b"\x7fELF-polymorph-obj-sample\n")
    write(os.path.join(d, "version.manifest"),
          f"build {variant}: abcdef cabaac\n".encode())
    cred = os.path.join(d, "credentials.file")
    write(cred, f"sensitive-access-token-{variant}\n".encode(), mode=0o600)
    write(os.path.join(d, "box.txt"),
          f"payload snapshot {variant}\n".encode(), mode=0o644)

    # printer-file fixture (gzip-deflated in most variants)
    place = os.path.join(dest, "place")
    printer_body = (
        f"lasercraft feed pagelist\nsprocket-{variant}:012864374398\n"
        "media=plain-100pt\ncopies:1\n<primer-12px>\n"
    ).encode()
    printer = gzip_bytes(printer_body) if gzip_printer else printer_body
    write(os.path.join(place, f"feed-{variant}.printer"), printer)

    # payloads: coexisting live log + a tar archive with a hexdumped binary.
    pl = os.path.join(dest, "payloads")
    binary = build_elf(exit_code=40 + variant)          # out.bin must equal this
    hexmap = hexdump_xxd(binary)
    coexisting = b"[journal] seq " * 9000 + f" end-{variant}\n".encode()

    staging = os.path.join(dest, "_stage")
    write(os.path.join(staging, "readme.txt"),
          b"stream only map.hex; do not expand the archive\n")
    write(os.path.join(staging, "map.hex"), hexmap)
    write(os.path.join(staging, "big.bin"), bytes((variant + 7) % 256) * 50000)
    write(os.path.join(staging, "raw.log"),
          b"[SENSITIVE-CLONE] never touch\n")
    apath = os.path.join(pl, "archive.tar.gz")
    os.makedirs(pl, exist_ok=True)
    with tarfile.open(apath, "w:gz") as tar:
        for name in ("readme.txt", "map.hex", "big.bin", "raw.log"):
            tar.add(os.path.join(staging, name), arcname=name)
    write(os.path.join(pl, "raw.log"), coexisting)   # live log must stay intact
    shutil.rmtree(staging, ignore_errors=True)

    return {
        "printer": printer, "printer_gzip": gzip_printer,
        "binary": binary, "main": main, "example": example,
        "coexisting": coexisting,
    }


def clean(target):
    if os.path.exists(target):
        shutil.rmtree(target)


def main():
    clean(ENVFILES)
    build_tree(ENVFILES, 0, gzip_printer=True)
    clean(HIDDEN)
    build_tree(os.path.join(HIDDEN, "H1"), 1, gzip_printer=True)     # normal
    build_tree(os.path.join(HIDDEN, "H2"), 2, gzip_printer=False)    # printer is plaintext
    build_tree(os.path.join(HIDDEN, "H3"), 3, gzip_printer=True,
               with_cache=False)                                      # no pycache dir
    print("fixtures generated")


if __name__ == "__main__":
    main()