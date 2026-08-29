# Zephyr — a small, clean-room, single-pass compiler

`zep` is a compiler I wrote from scratch for **Zephyr**, a deliberately tiny
C-like language with unsigned byte buffers, signed integer arithmetic,
control flow, user functions, and two stream builtins. It is self-contained
(only libc) and shares no code or text with any third-party compiler. Its
job in this lab is to be a small toolchain you build from source and then
use to compile the bundled decoder and the encoder you author.

## Building

    make            # build zepc from zep.c with the host C compiler
    make install    # install into $(PREFIX)/bin/cc  (default PREFIX=/app/cc)

## Usage

    zep [-c] [-o OUT] SOURCE.zh

- Without `-c`: parse `SOURCE.zh`, emit equivalent portable C, and drive the
  host C compiler to produce a native executable at `OUT`.
- With `-c`: emit a relocatable object at `OUT`.
- `-std=` flags are accepted for interface compatibility and ignored.

## The Zephyr language (source ends in `.zh`)

### Data
- `byte BUF[1024];` — a file-scope unsigned-byte buffer. Declared at the top
  level; `SIZE` is an integer literal.
- `int x;` / `int x = EXPR;` — signed 32-bit locals, declared at the start of
  a block inside a function.

### Functions
- `int name (int a, int b) { ... }` — user function; parameters are `int`.
  Define a function before calling it.
- `int main(){ ... }` — the entry point; it returns an `int`.

### Statements
- `EXPR;` and a bare `;`
- `x = EXPR;`
- `buf[i] = EXPR;`
- `if (COND) STMT  [else STMT]`
- `while (COND) STMT`
- `break;`
- `return [EXPR];`
- `{ STMT... }` — a block

### Expressions
Integer literals (decimal and `0x` hex), binary `+ - * / %`, comparisons
`< <= > >= == !=`, logical `&& ||`, bitwise `& |`, unary `!`, parentheses,
indexing `BUF[i]`, and calls:

- `read_all(BUF)` — read all of stdin into `BUF`, returning the byte count.
- `out(BYTE)` — write the low byte of `BYTE` to stdout.

### Diagnostics
Unexpected tokens, a missing `}` or `;`, or a call before its definition are
rejected with a `zep:` message and a non-zero exit status.

## Implementation notes
`zep.c` is deliberately small and readable: a hand-written tokenizer, a
recursive-descent parser that climbs precedence, and a single-pass emitter to
C. The tiny stream helpers `z_read_all` and `z_out` are prepended to every
generated program so a Zephyr program needs no link-time libraries.