#!/usr/bin/env bash
# Disk headroom guard for the v4.1 authoring wave.
#
# 53 tasks are authored concurrently, each building a Docker image that installs
# a language toolchain, a database server or a monitoring stack. Two things leak:
#
#   - build cache from every rebuild;
#   - untagged images. Each harbor trial build leaves one, 671MB to 2.7GB, and
#     `docker images` shows 60 of them as <none>:<none>. They are NOT caught by a
#     plain `docker image prune -f` until they age out of any reference, so the
#     prune here is filtered by age instead.
#
# The host is also running an unrelated 24-container job, so nothing here may
# touch a tagged image or a container. Both prunes are age-filtered: cache older
# than 30m and untagged images older than 20m. Docker additionally refuses to
# remove anything a running container or an in-flight build is using, so the age
# filter is belt and braces. The cost of pruning too eagerly is a slower rebuild,
# never a broken one.
#
# Stops when /tmp/v41-wave-done exists, or after HOURS hours.
#
# Usage: bash runs/disk-keeper-v41.sh [floor_gb] [hours]
set -uo pipefail
FLOOR=${1:-90}
HOURS=${2:-24}
SENTINEL=/tmp/v41-wave-done
end=$(( $(date +%s) + HOURS * 3600 ))
rm -f "$SENTINEL"
while true; do
  free=$(df --output=avail -BG /var/lib/docker 2>/dev/null | tail -1 | tr -dc '0-9')
  [ -z "$free" ] && free=999
  if [ "$free" -lt "$FLOOR" ]; then
    echo "[disk] $(date +%H:%M:%S) free=${free}G below ${FLOOR}G -> pruning"
    docker image prune -f --filter "until=20m" >/tmp/v41-disk-keeper-img.log 2>&1
    echo "[disk]   images: $(tail -1 /tmp/v41-disk-keeper-img.log)"
    docker builder prune -f --filter "until=30m" >/tmp/v41-disk-keeper.log 2>&1
    echo "[disk]   cache:  $(tail -1 /tmp/v41-disk-keeper.log)"
    echo "[disk]   now free=$(df --output=avail -BG /var/lib/docker | tail -1 | tr -dc '0-9')G"
  else
    echo "[disk] $(date +%H:%M:%S) free=${free}G ok"
  fi
  [ -f "$SENTINEL" ] && { echo "[disk] sentinel present, exiting"; break; }
  [ "$(date +%s)" -ge "$end" ] && { echo "[disk] ${HOURS}h elapsed, exiting"; break; }
  sleep 300
done
