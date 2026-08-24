#!/bin/bash
# Verifier for skill-ocr-transcription: letters-only normalized transcript must
# equal "ALLWORKANDNOPLAYMAKESJACKADULLBOY".
mkdir -p /logs/verifier
reward=0

if [ -f /app/transcript.txt ]; then
  norm=$(tr 'a-z' 'A-Z' < /app/transcript.txt | tr -cd 'A-Z')
  expected="ALLWORKANDNOPLAYMAKESJACKADULLBOY"
  if [ "$norm" = "$expected" ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0