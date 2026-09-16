# Building Mbed TLS in this container (no network)

The tree at `/app/src` is a shallow clone of `Mbed-TLS/mbedtls` at the pinned
parent commit, with its two submodules (`framework`,
`tf-psa-crypto` + nested `tf-psa-crypto/framework`) checked out. A warm
CMake build already exists at `/app/src/build` (library plus the
`test_suite_pkcs7` and `test_suite_x509parse` test binaries were compiled at
image build time), so you only build incrementally.

```bash
cd /app/src

# incremental rebuild of the module's own test program (fast; -j1)
cmake --build build --target test_suite_pkcs7 -j1

# run the module's own test suite (from the repo root, so the relative
# fixture paths in the suite resolve)
./build/tests/test_suite_pkcs7 | tail -5

# the x509-parse suite (pkcs7 embeds certificate parsing)
./build/tests/test_suite_x509parse | tail -3
```

If the warm `build/` directory is ever missing:
`cmake -B build -DENABLE_TESTING=ON . && cmake --build build --target test_suite_pkcs7 test_suite_x509parse -j1`

Never `git fetch`/`git pull`/`git clone` — there is no network and nothing
else is needed.