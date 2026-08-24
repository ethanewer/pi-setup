#!/usr/bin/env bash
# Oracle: create the standard tensorflow checkpoint file group.
mkdir -p /app/checkpoint
printf 'model_checkpoint_path: "model"\n' > /app/checkpoint/checkpoint
printf '\x00' > /app/checkpoint/model.index
printf '\x00' > /app/checkpoint/model.data-00000-of-00001
echo done