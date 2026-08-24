#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0

if [ -f /app/checkpoint/checkpoint ] \
   && [ -f /app/checkpoint/model.index ] \
   && [ -f /app/checkpoint/model.data-00000-of-00001 ]; then
  line=$(grep '^model_checkpoint_path: "model"$' /app/checkpoint/checkpoint | head -1 | tr -d '\r')
  if [ "$line" = 'model_checkpoint_path: "model"' ]; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt