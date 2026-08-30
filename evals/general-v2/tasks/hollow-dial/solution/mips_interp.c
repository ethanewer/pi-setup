/* mips_interp.c - a small MIPS32 ELF interpreter (hollow-dial lab).
 *
 * Loads a 32-bit little-endian MIPS ELF executable (a single PT_LOAD segment),
 * sets the guest stack pointer, and runs the instruction stream from e_entry,
 * emulating registers and memory.  Guest `syscall` uses the documented ABI:
 *   $v0 = 4004  write(fd=$a0, addr=$a1, count=$a2)  (fd 1 -> stdout, 2 -> stderr)
 *   $v0 = 4001  exit(status=$a0)                     (interpreter exits with that code)
 * Exit codes: 0 guest exit(0); guest exit(N) -> N; 3 unsupported instruction;
 * 4 unknown syscall; 5 out-of-guest memory; 6 instruction budget exceeded.
 * Usage: mips_interp <elf-file>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MEMSZ   (128u * 1024u * 1024u)   /* flat guest address space */
#define SP_INIT 0x07fff000u
#define ICAP    (200u * 1000u * 1000u)

static uint8_t *mem;
static int32_t regs[32];
static uint32_t pc;

static void perr(const char *msg) {
    fprintf(stderr, "mips: %s (pc=0x%08x)\n", msg, pc);
}

static int inmem(uint32_t a, size_t n) {
    return a <= MEMSZ && n <= MEMSZ && (uint64_t)a + n <= MEMSZ;
}

static uint32_t ld32(uint32_t a) {
    return (uint32_t)mem[a] | ((uint32_t)mem[a + 1] << 8)
         | ((uint32_t)mem[a + 2] << 16) | ((uint32_t)mem[a + 3] << 24);
}

static void st32(uint32_t a, uint32_t v) {
    mem[a] = (uint8_t)v; mem[a + 1] = (uint8_t)(v >> 8);
    mem[a + 2] = (uint8_t)(v >> 16); mem[a + 3] = (uint8_t)(v >> 24);
}

static uint16_t ld16le(uint32_t a) { return (uint16_t)(mem[a] | (mem[a + 1] << 8)); }
static void st16le(uint32_t a, uint16_t v) { mem[a] = (uint8_t)v; mem[a + 1] = (uint8_t)(v >> 8); }

static uint16_t rd16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t rd32w(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* returns 0 on success, negative on error */
static int load_elf(const char *path, uint32_t *entry) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "mips: cannot open %s\n", path); return -1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); rewind(f);
    if (sz < 52) { fprintf(stderr, "mips: file too small for ELF header\n"); fclose(f); return -1; }
    uint8_t *buf = malloc((size_t)sz);
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fclose(f); free(buf); return -1; }
    fclose(f);

    if (!(buf[0] == 0x7f && buf[1] == 'E' && buf[2] == 'L' && buf[3] == 'F')) {
        fprintf(stderr, "mips: not an ELF file\n"); free(buf); return -1;
    }
    if (buf[4] != 1) { fprintf(stderr, "mips: not ELFCLASS32\n"); free(buf); return -1; }
    if (buf[5] != 1) { fprintf(stderr, "mips: not little-endian\n"); free(buf); return -1; }
    if (rd16(buf + 18) != 8) { fprintf(stderr, "mips: not EM_MIPS\n"); free(buf); return -1; }
    uint32_t e_entry = rd32w(buf + 24);
    uint32_t e_phoff = rd32w(buf + 28);
    uint16_t e_phentsize = rd16(buf + 42);
    uint16_t e_phnum = rd16(buf + 44);

    for (int i = 0; i < (int)e_phnum; i++) {
        uint32_t ph = e_phoff + (uint32_t)i * e_phentsize;
        uint32_t p_type = rd32w(buf + ph);
        if (p_type != 1) continue;             /* PT_LOAD */
        uint32_t p_offset = rd32w(buf + ph + 4);
        uint32_t p_vaddr = rd32w(buf + ph + 8);
        uint32_t p_filesz = rd32w(buf + ph + 16);
        uint32_t p_memsz = rd32w(buf + ph + 20);
        if (p_filesz > (uint32_t)sz || p_offset + p_filesz > (uint32_t)sz) {
            fprintf(stderr, "mips: segment extends past file\n"); free(buf); return -1;
        }
        if (!inmem(p_vaddr, p_memsz)) {
            fprintf(stderr, "mips: segment out of guest memory\n"); free(buf); return -1;
        }
        memcpy(mem + p_vaddr, buf + p_offset, p_filesz);
        if (p_memsz > p_filesz) memset(mem + p_vaddr + p_filesz, 0, p_memsz - p_filesz);
    }
    free(buf);
    *entry = e_entry;
    return 0;
}

static int do_syscall(void) {
    uint32_t v0 = (uint32_t)regs[2];
    if (v0 == 4004) {               /* write */
        int fd = (int)regs[4];
        uint32_t a = (uint32_t)regs[5];
        uint32_t n = (uint32_t)regs[6];
        if (!inmem(a, n)) { perr("write syscall outside guest memory"); return 5; }
        if (n) {
            if (fd == 1) fwrite(mem + a, 1, n, stdout);
            else if (fd == 2) fwrite(mem + a, 1, n, stderr);
        }
        regs[2] = (int32_t)n;
        return 0;
    }
    if (v0 == 4001) {               /* exit */
        fflush(stdout); fflush(stderr);
        exit((int)regs[4] & 0xff);
    }
    perr("unknown syscall number"); return 4;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: mips_interp <elf-file>\n"); return 2; }
    mem = (uint8_t *)calloc(1, MEMSZ);
    if (!mem) { fprintf(stderr, "mips: cannot allocate guest memory\n"); return 2; }
    uint32_t entry = 0;
    if (load_elf(argv[1], &entry) != 0) { free(mem); return 2; }
    memset(regs, 0, sizeof(regs));
    regs[29] = (int32_t)SP_INIT;      /* $sp */
    pc = entry;

    uint64_t count = 0;
    for (;;) {
        if (++count > (uint64_t)ICAP) { perr("instruction budget exhausted"); free(mem); return 6; }
        if (!inmem(pc, 4)) { perr("instruction fetch outside guest memory"); free(mem); return 5; }
        uint32_t w = ld32(pc);
        pc += 4;
        uint32_t op = w >> 26;
        uint32_t rs = (w >> 21) & 31, rt = (w >> 16) & 31,
                 rd = (w >> 11) & 31, sh = (w >> 6) & 31, funct = w & 0x3f;
        int32_t imm16 = (int16_t)(w & 0xffff);

        switch (op) {
        case 0x00: {                 /* R-type */
            switch (funct) {
            case 0x00: regs[rd] = regs[rt] << sh; break;
            case 0x02: regs[rd] = (uint32_t)regs[rt] >> sh; break;
            case 0x03: regs[rd] = regs[rt] >> sh; break;
            case 0x08: pc = (uint32_t)regs[rs]; break;
            case 0x0c: { int r = do_syscall(); if (r) { free(mem); return r; } break; }
            case 0x21: regs[rd] = regs[rs] + regs[rt]; break;
            case 0x23: regs[rd] = regs[rs] - regs[rt]; break;
            case 0x24: regs[rd] = regs[rs] & regs[rt]; break;
            case 0x25: regs[rd] = regs[rs] | regs[rt]; break;
            case 0x26: regs[rd] = regs[rs] ^ regs[rt]; break;
            case 0x27: regs[rd] = ~(regs[rs] | regs[rt]); break;
            case 0x2a: regs[rd] = (regs[rs] < regs[rt]) ? 1 : 0; break;
            case 0x2b: regs[rd] = ((uint32_t)regs[rs] < (uint32_t)regs[rt]) ? 1 : 0; break;
            default: perr("unsupported R-type funct"); free(mem); return 3;
            }
            break;
        }
        case 0x02: pc = (pc & 0xf0000000u) | ((w & 0x03ffffffu) << 2); break;
        case 0x03: regs[31] = (int32_t)pc; pc = (pc & 0xf0000000u) | ((w & 0x03ffffffu) << 2); break;
        case 0x04: if (regs[rs] == regs[rt]) pc += (uint32_t)(imm16 << 2); break;
        case 0x05: if (regs[rs] != regs[rt]) pc += (uint32_t)(imm16 << 2); break;
        case 0x06: if (regs[rs] <= 0) pc += (uint32_t)(imm16 << 2); break;
        case 0x07: if (regs[rs] > 0) pc += (uint32_t)(imm16 << 2); break;
        case 0x01:
            if (rt == 0) { if (regs[rs] < 0) pc += (uint32_t)(imm16 << 2); }
            else if (rt == 1) { if (regs[rs] >= 0) pc += (uint32_t)(imm16 << 2); }
            else { perr("unknown REGIMM branch"); free(mem); return 3; }
            break;
        case 0x08: regs[rt] = regs[rs] + imm16; break;                     /* addi */
        case 0x09: regs[rt] = regs[rs] + imm16; break;                     /* addiu */
        case 0x0a: regs[rt] = (regs[rs] < imm16) ? 1 : 0; break;           /* slti */
        case 0x0b: regs[rt] = ((uint32_t)regs[rs] < (uint32_t)(int32_t)imm16) ? 1 : 0; break;
        case 0x0c: regs[rt] = regs[rs] & (uint16_t)imm16; break;          /* andi */
        case 0x0d: regs[rt] = regs[rs] | (uint16_t)imm16; break;          /* ori */
        case 0x0e: regs[rt] = regs[rs] ^ (uint16_t)imm16; break;          /* xori */
        case 0x0f: regs[rt] = (int32_t)((uint16_t)imm16 << 16); break;    /* lui */
        case 0x20: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 1)) { perr("lb outside memory"); free(mem); return 5; }
                     regs[rt] = (int8_t)mem[ea]; break; }
        case 0x24: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 1)) { perr("lbu outside memory"); free(mem); return 5; }
                     regs[rt] = (int32_t)mem[ea]; break; }
        case 0x23: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 4)) { perr("lw outside memory"); free(mem); return 5; }
                     regs[rt] = (int32_t)ld32(ea); break; }
        case 0x25: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 2)) { perr("lhu outside memory"); free(mem); return 5; }
                     regs[rt] = (int16_t)ld16le(ea); break; }
        case 0x28: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 1)) { perr("sb outside memory"); free(mem); return 5; }
                     mem[ea] = (uint8_t)(regs[rt] & 0xff); break; }
        case 0x29: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 2)) { perr("sh outside memory"); free(mem); return 5; }
                     st16le(ea, (uint16_t)(regs[rt] & 0xffff)); break; }
        case 0x2b: { uint32_t ea = (uint32_t)((int32_t)regs[rs] + (int32_t)imm16);
                     if (!inmem(ea, 4)) { perr("sw outside memory"); free(mem); return 5; }
                     st32(ea, (uint32_t)regs[rt]); break; }
        default:
            perr("unsupported opcode");
            free(mem);
            return 3;
        }
    }
}