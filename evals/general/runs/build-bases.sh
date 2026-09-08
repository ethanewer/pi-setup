#!/bin/bash
set -uo pipefail
cd /home/ee/pi-setup/evals/general/bases
build() {
  local tag=$1 df=$2
  echo "=== building bench-base:$tag from $df"
  docker build -t "bench-base:$tag" -f "$df" . 2>&1 | tail -5
  echo "=== done bench-base:$tag rc=${PIPESTATUS[0]}"
}
build python-3.12 python-3.12.Dockerfile &
P1=$!
build ubuntu-24.04 ubuntu-24.04.Dockerfile &
P2=$!
build node-22 node-22.Dockerfile &
P3=$!
echo "=== pulling texlive/texlive"
docker pull texlive/texlive > /tmp/texlive-pull.log 2>&1 && echo "=== texlive pull ok" || echo "=== texlive pull FAILED" &
P4=$!
wait $P1 $P2 $P3 $P4
echo "=== ALL BASE BUILDS COMPLETE"
docker images | grep -E "bench-base|texlive"
