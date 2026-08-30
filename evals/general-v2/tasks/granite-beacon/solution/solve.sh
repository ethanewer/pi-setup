#!/bin/bash
# Oracle for tasks/granite-beacon (executes-deliverable).
# Does the REAL work for all five build paths and produces every /app
# deliverable by running the actual tools.  Never reads /tests.
set -u

export OPAMROOT=${OPAMROOT:-/root/.opam}
# Bound build parallelism so the OCaml/Coq/CompCert source builds fit the
# container memory budget even when several sweep containers share the host.
export OPAMJOBS=${OPAMJOBS:-4}

echo "== [0] ensure CompCert toolchain =="
install_compcert() {
  opam init --disable-sandboxing --bare -y >/tmp/oo1.log 2>&1 || true
  opam switch create default ocaml-base-compiler >/tmp/oo2.log 2>&1 || true
  opam repo add coq-repo -y https://coq.inria.fr/opam/released >/tmp/oo3.log 2>&1 || true
  opam update -y >/tmp/oo4.log 2>&1 || true
  opam install -y coq-compcert >/tmp/oo5.log 2>&1 || return 1
  eval "$(opam env --switch=default 2>/dev/null)"
  command -v ccomp >/dev/null 2>&1
}
if ! command -v ccomp >/dev/null 2>&1; then
  ok=0
  for attempt in 1 2 3; do
    if install_compcert; then ok=1; break; fi
    echo "CompCert install attempt $attempt failed; retrying" >&2
    sleep 10
  done
  if [ "$ok" != 1 ]; then
    echo "CompCert install failed after retries" >&2
    exit 1
  fi
fi
eval "$(opam env --switch=default 2>/dev/null)"
ccomp --version || { echo "CompCert install failed"; exit 1; }

echo "== [1] modernize legacy C++ /app/modernized =="
# Remove the obsolete constructs so choron builds under C++17: drop the legacy
# <hash> include, retarget auto_ptr->unique_ptr, and delete 'register'.
sed -i '/#include <hash>/d' /app/modernized/src/main.cpp
sed -i 's/std::auto_ptr<std::string>/std::unique_ptr<std::string>/g' /app/modernized/src/main.cpp
sed -i 's/\bregister int /        int /g' /app/modernized/src/main.cpp
cmake -S /app/modernized -B /app/modernized/build >/tmp/cm1.log 2>&1
cmake --build /app/modernized/build >>/tmp/cm1.log 2>&1
/app/modernized/build/choron <<'EOF' >/tmp/choron.out
alto = 7482
tempo=0
beacon = -18
EOF
test -x /app/modernized/build/choron || { echo "modernize FAILED"; exit 1; }

echo "== [2] port the codec to Rust /app/compressor =="
cat > /app/compressor/src/lib.rs <<'RSEOF'
//! beaconpack — clean-room byte-prefix run-length codec (port of the reference
//! C implementation).  See instruction part 2.
pub fn compress(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + data.len());
    out.push(0xC5);
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    let mut i = 0;
    while i < data.len() {
        let mut j = i;
        while j < data.len() && data[j] == data[i] && (j - i) < 255 {
            j += 1;
        }
        out.push(((j - i) as u8) - 1);
        out.push(data[i]);
        i = j;
    }
    out
}
pub fn decompress(code: &[u8]) -> Result<Vec<u8>, &'static str> {
    if code.len() < 5 || code[0] != 0xC5 {
        return Err("bad magic");
    }
    let total = u32::from_le_bytes([code[1], code[2], code[3], code[4]]) as usize;
    let mut out = Vec::new();
    let mut i = 5;
    while out.len() < total {
        if i + 1 >= code.len() {
            return Err("truncated");
        }
        let rlen = (code[i] as usize) + 1;
        let b = code[i + 1];
        if out.len() + rlen > total {
            return Err("overshoot");
        }
        i += 2;
        out.resize(out.len() + rlen, b);
    }
    Ok(out)
}

pub fn roundtrip_ok(data: &[u8]) -> bool {
    match decompress(&compress(data)) {
        Ok(v) => v == data,
        Err(_) => false,
    }
}
RSEOF
cd /app/compressor
cargo test 2>&1 | tee /app/compressor_tests.log
cargo build --release >>/app/compressor_tests.log 2>&1
test -x /app/compressor/target/release/probe || { echo "compressor FAILED"; exit 1; }

echo "== [3] headless legacy tool build =="
cmake -S /app/legacy_tool -B /app/legacy_tool/build -DENABLE_GUI=OFF >/tmp/lt.log 2>&1
cmake --build /app/legacy_tool/build >>/tmp/lt.log 2>&1
mkdir -p /app/legacy_tool/bin
cp /app/legacy_tool/build/transwc /app/legacy_tool/bin/transwc
printf 'HEADLESS_BUILD_OK /app/legacy_tool/bin/transwc\n' > /app/legacy_build.log
test -x /app/legacy_tool/bin/transwc || { echo "legacy FAILED"; exit 1; }

echo "== [4] CompCert ELF =="
eval "$(opam env --switch=default 2>/dev/null)"
ccomp -O2 /app/verifymesh/beacon.c -o /app/compcert_bin 2>/tmp/ccb.log
strip /app/compcert_bin
objcopy --remove-section .comment /app/compcert_bin 2>/dev/null || true
file /app/compcert_bin
test -x /app/compcert_bin || { echo "compcert FAILED"; exit 1; }

echo "== [5] optimization binaries + sizes.tsv =="
mkdir -p /app/opt
gcc -O0 /app/opt/kern.c -o /app/opt/gcc_O0
gcc -O2 /app/opt/kern.c -o /app/opt/gcc_O2
clang -O2 /app/opt/kern.c -o /app/opt/clang_O2
printf '%s\t%s\n' /app/opt/gcc_O0     "$(stat -c %s /app/opt/gcc_O0)"    >  /app/sizes.tsv
printf '%s\t%s\n' /app/opt/gcc_O2     "$(stat -c %s /app/opt/gcc_O2)"    >> /app/sizes.tsv
printf '%s\t%s\n' /app/opt/clang_O2   "$(stat -c %s /app/opt/clang_O2)"  >> /app/sizes.tsv
printf '%s\t%s\n' /app/compcert_bin   "$(stat -c %s /app/compcert_bin)"  >> /app/sizes.tsv
cat /app/sizes.tsv

echo "SOLVE_DONE"
exit 0