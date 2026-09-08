#!/usr/bin/env bash
# Keep disk headroom during a long sweep. The v3.4 census rebuilds 161 task images
# because pinning the thread pools changed their Dockerfiles, and the build cache
# from those rebuilds grows faster than the sweep finishes. Only cache older than
# an hour is pruned, so nothing an in-flight build is using is touched, and it
# stops as soon as free space is comfortable again.
while true; do
  free=$(df --output=avail -BG /var/lib/docker 2>/dev/null | tail -1 | tr -dc '0-9')
  [ -z "$free" ] && free=999
  if [ "$free" -lt 90 ]; then
    echo "[disk] $(date +%H:%M:%S) free=${free}G -> pruning build cache older than 1h"
    docker builder prune -f --filter "until=1h" >/tmp/disk-keeper.log 2>&1
    tail -1 /tmp/disk-keeper.log | sed 's/^/[disk]   /'
    docker image prune -f >/tmp/disk-keeper2.log 2>&1
    echo "[disk]   now free=$(df --output=avail -BG /var/lib/docker | tail -1 | tr -dc '0-9')G"
  else
    echo "[disk] $(date +%H:%M:%S) free=${free}G ok"
  fi
  # stop once the census is done
  n=$(ls -1 /home/ee/general-eval-runs/jobs/v34-oracle-post/*/result.json 2>/dev/null | wc -l)
  if [ "$n" -ge 785 ]; then echo "[disk] census complete at $n/785, exiting"; break; fi
  sleep 600
done
