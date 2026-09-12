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
#   - TAGGED scratch images, which are the biggest of the three. Authoring and
#     review agents build ad-hoc images with names like `foo:dev`, `foo-review`,
#     `scratch-foo`, `bench-local:dbg1` and never remove them. Measured during the
#     v4.3 waves: 143 GB of scratch against 41 GB of build cache and 2.7 GB of
#     harbor trial images. Cache pruning alone cannot hold the floor when scratch
#     dominates, so images older than SCRATCH_MIN with no container attached are
#     removed too. Losing one costs an agent a rebuild, never a result, because
#     the acceptance gate builds from the task directory anyway.
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
SCRATCH_MIN=${3:-90}
SENTINEL=/tmp/v41-wave-done
# Never removed: the suite's own base images, and images belonging to other work
# on this host that this script has no business touching.
PROTECT='^(texlive/|bench-base:|847366387031\.|nvcr\.io|arc-)'
end=$(( $(date +%s) + HOURS * 3600 ))
rm -f "$SENTINEL"

prune_scratch() {
  # Tagged images, older than SCRATCH_MIN, with no container attached.
  docker ps -a --format '{{.Image}}' | sort -u > /tmp/v41-inuse.txt
  docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}' |
  while IFS=$'\t' read -r rt id created; do
    case "$rt" in '<none>:<none>') continue ;; esac
    echo "$rt" | grep -qE "$PROTECT" && continue
    case "$created" in
      *"second"*) continue ;;
    esac
    # keep anything newer than SCRATCH_MIN minutes. Docker renders ages as
    # "N seconds/minutes ago", "About an hour ago", then "N hours ago" and up, so
    # "About an hour" has to be converted rather than lumped in with the hours.
    case "$created" in
      *"About an hour"*) [ 60 -lt "$SCRATCH_MIN" ] && continue ;;
      *"minute"*)
        mins=$(echo "$created" | grep -oE '^[0-9]+' || echo 0)
        [ "$mins" -lt "$SCRATCH_MIN" ] && continue ;;
      *"hour"*|*"day"*|*"week"*|*"month"*|*"year"*) ;;
      *) continue ;;
    esac
    repo=${rt%%:*}
    grep -qxF "$repo" /tmp/v41-inuse.txt && continue
    grep -qxF "$rt" /tmp/v41-inuse.txt && continue
    docker rmi -f "$id" >/dev/null 2>&1 && echo "[disk]   scratch: removed $rt ($created)"
  done
}
while true; do
  free=$(df --output=avail -BG /var/lib/docker 2>/dev/null | tail -1 | tr -dc '0-9')
  [ -z "$free" ] && free=999
  if [ "$free" -lt "$FLOOR" ]; then
    echo "[disk] $(date +%H:%M:%S) free=${free}G below ${FLOOR}G -> pruning"
    docker image prune -f --filter "until=20m" >/tmp/v41-disk-keeper-img.log 2>&1
    echo "[disk]   untagged: $(tail -1 /tmp/v41-disk-keeper-img.log)"
    prune_scratch
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
