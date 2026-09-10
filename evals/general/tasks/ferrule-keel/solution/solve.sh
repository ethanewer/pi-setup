#!/bin/bash
# Oracle for ferrule-keel: builds the real tinycc tree with its own
# configure/make, installs it under /app/tccinst, drives it and the system
# gcc over the five shipped programs, records the outputs per the contract,
# and writes the diagnosis naming the documented divergence (C99 complex
# numbers, missing in tcc per tcc-doc.texi). Reads only /app/src and
# /app/programs; never /tests.
set -u
cd /app || exit 1

# ---- 1. build the compiler from the upstream tree --------------------------
cd /app/src
./configure --prefix=/app/tccinst >/dev/null
make >/dev/null || { echo "oracle: make failed" >&2; exit 1; }
make install >/dev/null || { echo "oracle: make install failed" >&2; exit 1; }
cd /app

test -x /app/tccinst/bin/tcc || { echo "oracle: no tcc binary" >&2; exit 1; }

# ---- 2. drive the built compiler over the five programs --------------------
mkdir -p /app/outputs
for prog in hello fib strings structs; do
    if /app/tccinst/bin/tcc -o "/tmp/$prog" "/app/programs/$prog.c" \
            >"/tmp/$prog.compile.log" 2>&1; then
        "/tmp/$prog" > "/app/outputs/$prog.out"
    else
        echo "oracle: tcc unexpectedly failed on $prog.c" >&2
        exit 1
    fi
done

# complex.c: tcc cannot build it (missing C99 complex numbers); record the
# tcc stderr verbatim and the gcc stdout.
if /app/tccinst/bin/tcc -o /tmp/complex /app/programs/complex.c \
        >"/tmp/complex.compile.log" 2>/app/outputs/complex.err; then
    echo "oracle: tcc unexpectedly compiled complex.c" >&2
    exit 1
fi
gcc -o /tmp/complex_gcc /app/programs/complex.c >/dev/null 2>&1 \
    || { echo "oracle: gcc failed on complex.c" >&2; exit 1; }
/tmp/complex_gcc > /app/outputs/complex.gcc.out

# The four stdout deliverables, named literally (the loop above wrote them).
for f in /app/outputs/hello.out /app/outputs/fib.out \
         /app/outputs/strings.out /app/outputs/structs.out; do
    [ -s "$f" ] || { echo "oracle: $f missing or empty" >&2; exit 1; }
done

# ---- 3. diagnosis -----------------------------------------------------------
cat > /app/diagnosis.md <<'MD'
## Which program tcc handles differently, and why

The program is `complex.c`. It is the only one of the five that the tcc I
built cannot compile: tcc exits nonzero while the system gcc compiles and
runs it.

The responsible feature is the C99 type `complex` (complex numbers): tcc does
not implement them. `/app/src/tcc-doc.texi`, section "ISOC99 extensions",
states this explicitly: "Currently missing items are: complex and imaginary
numbers." tcc's own preprocessor aborts on the system C library's
`<complex.h>` (the error chain ends inside
`/usr/include/x86_64-linux-gnu/bits/cmathcalls.h`), so the failure surfaces
before any user code is generated, while gcc supports the full C99 complex
type family (`double complex`, `I`, `creal`, `cimag`, `conj`).

The first error line tcc prints is:

    In file included from /app/programs/complex.c:2:

followed by the parser errors inside glibc's `complex.h`. Everything about
the other four programs is identical between tcc and gcc: division and modulo
semantics, shift and sign-extension behaviour, struct/bitfield layout, and
floating-point printing all agree byte for byte.
MD

echo "oracle: build+outputs+diagnosis complete"