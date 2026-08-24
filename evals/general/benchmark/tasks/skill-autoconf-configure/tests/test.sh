#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/pkg/defs.h ]; then
  has_feature=0; has_opt=0
  grep -q '^#define[[:space:]]*WITH_FEATURE[[:space:]]*blas' /app/pkg/defs.h && has_feature=1
  grep -q '^#define[[:space:]]*ENABLE_OPT[[:space:]]*64' /app/pkg/defs.h && has_opt=1
  if [ "$has_feature$has_opt" = "11" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt