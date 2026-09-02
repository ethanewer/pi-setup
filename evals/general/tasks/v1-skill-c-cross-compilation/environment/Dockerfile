FROM bench-base:ubuntu-24.04

WORKDIR /app

# Install the AArch64 cross GCC toolchain (compiler + binutils) plus the
# 'file' program used by the verifier.
RUN apt-get update && \
    apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu file && \
    rm -rf /var/lib/apt/lists/*

# The cross-gcc driver locates its 'as' (assembler) and 'ld' (linker) helper
# binaries by plain exec name on PATH.  The cross toolchain installs them
# under the 'aarch64-linux-gnu-' prefix in /usr/bin, so expose exec-name
# dispatchers that forward to those target-specific tools.
RUN mkdir -p /usr/local/crossbin && \
    printf '#!/bin/bash\nexec /usr/bin/aarch64-linux-gnu-as "$@"\n' > /usr/local/crossbin/as && \
    printf '#!/bin/bash\nexec /usr/bin/aarch64-linux-gnu-ld "$@"\n' > /usr/local/crossbin/ld && \
    chmod +x /usr/local/crossbin/as /usr/local/crossbin/ld

ENV PATH="/usr/local/crossbin:${PATH}"

RUN mkdir -p /app/cross && \
    cat > /app/cross/hello.c <<'SRC_END'
#include <stdio.h>
int main(void) {
    printf("hello from arm64\n");
    return 0;
}
SRC_END