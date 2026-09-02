"""Generate the two .wasm fixture files shipped to /app/data at build time.

mem.wasm : a minimal module exporting probe()[->i32] returning an index into
           linear memory, plus exports.memory, with "JETTY_WASM" stored at that
           offset. probe() returns offset 9; memory[9] == 0x4a ('J').
bad.wasm : a deliberately non-wasm byte blob used to exercise wasm_probe's
           malformed-input error path.
"""
import os

OUT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

def build_mem():
    secs = []
    magic = b"\x00asm"; ver = b"\x01\x00\x00\x00"
    # type section (id 1): 1 func () -> i32
    tp = b"\x01\x60\x00\x01\x7f"
    secs.append(b"\x01" + bytes([len(tp)]) + tp)
    # function section (id 3): one func, type 0
    fc = b"\x01\x00"
    secs.append(b"\x03" + bytes([len(fc)]) + fc)
    # memory section (id 5): 1 memory, min 1 page (64 KiB)
    mc = b"\x01\x00\x01"
    secs.append(b"\x05" + bytes([len(mc)]) + mc)
    # export section (id 7): probe(func idx 0) and memory(mem idx 0)
    nm = b"probe"
    ex = b"\x02" + bytes([len(nm)]) + nm + b"\x00\x00" + b"\x06memory\x02\x00"
    secs.append(b"\x07" + bytes([len(ex)]) + ex)
    # code section (id 10): body locals0, i32.const 9, end
    offset = 9
    body = b"\x00" + b"\x41" + bytes([offset]) + b"\x0b"
    code = b"\x01" + bytes([len(body)]) + body
    secs.append(b"\x0a" + bytes([len(code)]) + code)
    # data section (id 11): mem 0, offset 9, "JETTY_WASM"
    data = b"JETTY_WASM"
    ds = b"\x01" + b"\x00" + b"\x41" + bytes([offset]) + b"\x0b" + bytes([len(data)]) + data
    secs.append(b"\x0b" + bytes([len(ds)]) + ds)
    return magic + ver + b"".join(secs)

mem = build_mem()
with open(os.path.join(OUT, "mem.wasm"), "wb") as fh:
    fh.write(mem)
with open(os.path.join(OUT, "bad.wasm"), "wb") as fh:
    fh.write(b"This is not a WebAssembly binary.")
print("wrote %d-byte mem.wasm and bad.wasm" % len(mem))