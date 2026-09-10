#!/usr/bin/env bash
# kedd launcher: exec the daemon in the foreground (the process the operator
# signals is the JVM itself). All arguments are passed through to the daemon.
set -euo pipefail
cd "$(dirname "$0")"
exec java -cp build cairn.Keddaemon "$@"