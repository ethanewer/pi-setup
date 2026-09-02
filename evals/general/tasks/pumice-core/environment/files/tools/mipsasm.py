#!/usr/bin/env python3
"""Authoring helper: a tiny big-endian MIPS32 ELF assembler for pumice-core.

Supports the instruction subset documented in the task, labels, .text/.data,
.byte/.half/.word/.asciz/.space/.align, and pseudo-ops li/la/move/nop/b/beqz/bnez.
Emits an ELF32 big-endian image with two PT_LOAD segments:
  text @ 0x00100000 (RX), data @ 0x00200000 (RW); entry = 0x00100000.
"""
import re, struct, sys

REGS = {"zero": 0, "at": 1, "v0": 2, "v1": 3, "a0": 4, "a1": 5, "a2": 6, "a3": 7,
        "t0": 8, "t1": 9, "t2": 10, "t3": 11, "t4": 12, "t5": 13, "t6": 14, "t7": 15,
        "s0": 16, "s1": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23,
        "t8": 24, "t9": 25, "k0": 26, "k1": 27, "gp": 28, "sp": 29, "fp": 30, "ra": 31}

R_FUNCT = {"sll": 0x00, "srl": 0x02, "sra": 0x03, "sllv": 0x04, "srlv": 0x06,
           "srav": 0x07, "jr": 0x08, "jalr": 0x09, "syscall": 0x0C,
           "mfhi": 0x10, "mthi": 0x11, "mflo": 0x12, "mtlo": 0x13,
           "mult": 0x18, "multu": 0x19, "div": 0x1A, "divu": 0x1B,
           "add": 0x20, "addu": 0x21, "sub": 0x22, "subu": 0x23,
           "and": 0x24, "or": 0x25, "xor": 0x26, "nor": 0x27,
           "slt": 0x2A, "sltu": 0x2B}
I_OP = {"beq": 0x04, "bne": 0x05, "blez": 0x06, "bgtz": 0x07,
        "addi": 0x08, "addiu": 0x09, "slti": 0x0A, "sltiu": 0x0B,
        "andi": 0x0C, "ori": 0x0D, "xori": 0x0E, "lui": 0x0F,
        "lb": 0x20, "lh": 0x21, "lw": 0x23, "lbu": 0x24, "lhu": 0x25,
        "sb": 0x28, "sh": 0x29, "sw": 0x2B}
J_OP = {"j": 0x02, "jal": 0x03}

TEXT_ORG = 0x00100000
DATA_ORG = 0x00200000


def parse_reg(tok):
    tok = tok.strip()
    if tok.startswith("$"):
        tok = tok[1:]
    if tok.isdigit():
        return int(tok)
    return REGS[tok]


def imm_val(tok):
    return int(tok.strip(), 0)


def li_words(v):
    v &= 0xFFFFFFFF
    s = v if v < 0x80000000 else v - 0x100000000
    if -32768 <= s <= 32767 or 0 <= v <= 0xFFFF:
        return 1
    return 2


class Asm:
    def __init__(self):
        self.labels = {}          # name -> ("t", word_index) | ("d", byte_offset)
        self.items = []           # text items: (mnemonic, ops, line_no, words)
        self.twords = 0
        self.data = bytearray()
        self.section = "text"

    def err(self, msg, no):
        raise SyntaxError("line %d: %s" % (no, msg))

    def define_label(self, name, no):
        if name in self.labels:
            self.err("duplicate label " + name, no)
        if self.section == "text":
            self.labels[name] = ("t", self.twords)
        else:
            self.labels[name] = ("d", len(self.data))

    def label_addr(self, name, no):
        if name not in self.labels:
            self.err("unknown label " + name, no)
        kind, v = self.labels[name]
        return (TEXT_ORG + 4 * v) if kind == "t" else (DATA_ORG + v)

    def line(self, ln, no):
        ln = re.sub(r"#.*$", "", ln).strip()
        while True:
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:", ln)
            if not m:
                break
            self.define_label(m.group(1), no)
            ln = ln[m.end():].strip()
        if not ln:
            return
        parts = ln.split(None, 1)
        mn = parts[0].lower()
        ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        if mn == ".text":
            self.section = "text"; return
        if mn == ".data":
            self.section = "data"; return
        if mn == ".align":
            if self.section != "data":
                self.err(".align only in .data", no)
            n = 1 << imm_val(ops[0])
            while len(self.data) % n:
                self.data.append(0)
            return
        if mn == ".space":
            self.data.extend(b"\0" * imm_val(ops[0])); return
        if mn in (".byte", ".half", ".word") and self.section == "data":
            size = {".byte": 1, ".half": 2, ".word": 4}[mn]
            mask = (1 << (8 * size)) - 1
            for o in ops:
                self.data.extend((imm_val(o) & mask).to_bytes(size, "big"))
            return
        if mn in (".asciz", ".ascii"):
            if self.section != "data":
                self.err(mn + " only in .data", no)
            s = ops[0].strip().strip('"').encode().decode("unicode_escape")
            self.data.extend(s.encode("utf-8") + (b"\0" if mn == ".asciz" else b""))
            return
        if mn in (".byte", ".half", ".word") and self.section == "text":
            if mn != ".word":
                self.err(mn + " not allowed in .text", no)
            self.items.append((".word", ops, no, 1))
            return
        if mn == "nop":
            words = 1
        elif mn == "move":
            words = 1
        elif mn == "li":
            words = li_words(imm_val(ops[1]))
        elif mn == "la":
            words = 2
        elif mn in R_FUNCT or mn in I_OP or mn in J_OP:
            words = 1
        else:
            self.err("unknown mnemonic " + mn, no)
        self.items.append((mn, ops, no, words))
        self.twords += words

    def emit_r(self, rs, rt, rd, sh, funct):
        return struct.pack(">I", (rs << 21) | (rt << 16) | (rd << 11) | (sh << 6) | funct)

    def emit_i(self, op, rs, rt, imm):
        return struct.pack(">I", (op << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF))

    def encode_one(self, mn, ops, addr, no):
        R, I, J = R_FUNCT, I_OP, J_OP
        if mn == ".word":
            return struct.pack(">I", imm_val(ops[0]) & 0xFFFFFFFF)
        if mn == "nop":
            return self.emit_r(0, 0, 0, 0, 0)
        if mn == "move":
            return self.emit_r(parse_reg(ops[1]), 0, parse_reg(ops[0]), 0, R["addu"])
        if mn == "b":
            return self.encode_one("beq", ["$zero", "$zero", ops[0]], addr, no)
        if mn == "beqz":
            return self.encode_one("beq", [ops[0], "$zero", ops[1]], addr, no)
        if mn == "bnez":
            return self.encode_one("bne", [ops[0], "$zero", ops[1]], addr, no)
        if mn == "li":
            rd = parse_reg(ops[0]); v = imm_val(ops[1]) & 0xFFFFFFFF
            s = v if v < 0x80000000 else v - 0x100000000
            if -32768 <= s <= 32767:
                return self.emit_i(I["addiu"], 0, rd, s)
            if v <= 0xFFFF:
                return self.emit_i(I["ori"], 0, rd, v)
            return (self.emit_i(I["lui"], 0, rd, (v >> 16) & 0xFFFF) +
                    self.emit_i(I["ori"], rd, rd, v & 0xFFFF))
        if mn == "la":
            rd = parse_reg(ops[0]); v = self.label_addr(ops[1], no)
            return (self.emit_i(I["lui"], 0, rd, (v >> 16) & 0xFFFF) +
                    self.emit_i(I["ori"], rd, rd, v & 0xFFFF))
        if mn == "syscall":
            return self.emit_r(0, 0, 0, 0, R["syscall"])
        if mn in R:
            f = mn
            if f in ("sll", "srl", "sra"):
                return self.emit_r(0, parse_reg(ops[1]), parse_reg(ops[0]), imm_val(ops[2]), R[f])
            if f in ("sllv", "srlv", "srav"):
                return self.emit_r(parse_reg(ops[2]), parse_reg(ops[1]), parse_reg(ops[0]), 0, R[f])
            if f == "jr":
                return self.emit_r(parse_reg(ops[0]), 0, 0, 0, R[f])
            if f == "jalr":
                rd = parse_reg(ops[0]) if len(ops) == 1 else parse_reg(ops[1])
                rs = parse_reg(ops[-1])
                return self.emit_r(rs, 0, rd, 0, R[f])
            if f in ("mult", "multu", "div", "divu"):
                return self.emit_r(parse_reg(ops[0]), parse_reg(ops[1]), 0, 0, R[f])
            if f in ("mfhi", "mflo"):
                return self.emit_r(0, 0, parse_reg(ops[0]), 0, R[f])
            if f in ("mthi", "mtlo"):
                return self.emit_r(parse_reg(ops[0]), 0, 0, 0, R[f])
            return self.emit_r(parse_reg(ops[1]), parse_reg(ops[2]), parse_reg(ops[0]), 0, R[f])
        if mn in I:
            op = I[mn]
            if op in (0x04, 0x05):
                rs, rt = parse_reg(ops[0]), parse_reg(ops[1])
                off = (self.label_addr(ops[2], no) - (addr + 4)) >> 2
                return self.emit_i(op, rs, rt, off)
            if op in (0x06, 0x07):
                off = (self.label_addr(ops[1], no) - (addr + 4)) >> 2
                return self.emit_i(op, parse_reg(ops[0]), 0, off)
            if op == 0x0F:
                return self.emit_i(op, 0, parse_reg(ops[0]), imm_val(ops[1]))
            if op >= 0x20:
                m = re.match(r"^(-?\w+)?\((\$\w+)\)$", ops[1])
                if not m:
                    self.err("bad memory operand " + ops[1], no)
                off = imm_val(m.group(1)) if m.group(1) else 0
                return self.emit_i(op, parse_reg(m.group(2)), parse_reg(ops[0]), off)
            return self.emit_i(op, parse_reg(ops[1]), parse_reg(ops[0]), imm_val(ops[2]))
        if mn in J:
            tgt = self.label_addr(ops[0], no)
            return struct.pack(">I", (J[mn] << 26) | ((tgt >> 2) & 0x3FFFFFF))
        self.err("unknown mnemonic " + mn, no)

    def encode(self):
        blob = []
        addr = TEXT_ORG
        for mn, ops, no, words in self.items:
            try:
                blob.append(self.encode_one(mn, ops, addr, no))
            except SyntaxError:
                raise
            except Exception as e:
                raise SyntaxError("line %d (%s %s): %s" % (no, mn, ops, e))
            addr += 4 * words
        return b"".join(blob)


def build_elf(text_bytes, data_bytes):
    ehsize, phentsize, phnum = 52, 32, 2
    text_off = ehsize + phentsize * phnum
    data_off = text_off + len(text_bytes)
    entry = TEXT_ORG

    def ph(p_type, off, vaddr, filesz, memsz, flags):
        return struct.pack(">IIIIIIII", p_type, off, vaddr, vaddr, filesz, memsz, flags, 0x1000)

    ident = bytes([0x7F]) + b"ELF" + bytes([1, 2, 1, 0, 0]) + b"\0" * 7
    ehdr = ident + struct.pack(">HHIIIIIHHHHHH",
                               2, 8, 1, entry, ehsize, 0, 0x50001000,
                               ehsize, phentsize, phnum, 40, 0, 0)
    phdrs = ph(1, text_off, TEXT_ORG, len(text_bytes), len(text_bytes), 5) + \
            ph(1, data_off, DATA_ORG, len(data_bytes), len(data_bytes), 6)
    return ehdr + phdrs + text_bytes + bytes(data_bytes)


def assemble(src_text):
    a = Asm()
    for no, ln in enumerate(src_text.splitlines(), 1):
        a.line(ln, no)
    blob = a.encode()
    return build_elf(blob, bytes(a.data))


if __name__ == "__main__":
    src = open(sys.argv[1]).read()
    try:
        img = assemble(src)
    except SyntaxError as e:
        sys.exit("asm error: %s" % e)
    open(sys.argv[2], "wb").write(img)
    print("wrote", sys.argv[2])
