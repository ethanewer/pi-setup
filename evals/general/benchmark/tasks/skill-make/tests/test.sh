#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/Makefile ]; then
  if ( cd /app && make -s && [ -x /app/hello ] && [ "$(./hello 2>/dev/null | tr -d '\r')" = "BUILD_OK" ] ) ; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt