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
SCRATCH_MAX_H=${4:-72}
# Two thresholds. FLOOR is when pruning starts. ALERT is when the operator should
# be woken up. Below FLOOR but above ALERT the guard is doing its job and the
# oscillation is normal, so it logs quietly; the steady state observed during the
# v4.3 waves was free space cycling between about 72G and 129G with a prune every
# couple of hours, which needs no action and was waking the operator for nothing.
ALERT=${5:-50}
SENTINEL=/tmp/v41-wave-done
# Never removed:
#   - anything with a RepoDigest, which means it was PULLED from a registry and
#     is therefore somebody's base image, not agent scratch;
#   - the suite's own bases and harbor's own prebuilt infrastructure;
#   - images belonging to other work on this host;
#   - anything older than SCRATCH_MAX_H hours, which predates the waves this
#     guard was started for and is therefore by definition not their scratch.
# That last bound is the one that was missing. The first version of the scratch
# prune had a minimum age and no maximum, so on its first firing it walked
# straight back through twelve months of unrelated images on this host, including
# python:3.12-slim (the upstream parent of bench-base:python-3.12), alpine:3.19,
# busybox, the v1 alexgshaw/* task images, and about twenty locally built images
# from earlier exploratory work. An age window, not just an age floor, is what
# makes "agent scratch" mean the current agents.
PROTECT='^(texlive/|bench-base:|harbor|arc-|847366387031\.|nvcr\.)'
end=$(( $(date +%s) + HOURS * 3600 ))
rm -f "$SENTINEL"

in_window() {  # $1 = docker CreatedSince string; true only if inside the window
  local created=$1 mins
  case "$created" in
    *"second"*|*"About a minute"*) return 1 ;;
    *"minute"*)
      mins=$(echo "$created" | grep -oE '^[0-9]+' || echo 0)
      [ "$mins" -ge "$SCRATCH_MIN" ] && return 0
      return 1 ;;
    *"hour"*|*"About an hour"*)
      case "$created" in *"About an hour"*) mins=60 ;; *) mins=$(( $(echo "$created" | grep -oE '^[0-9]+') * 60 )) ;; esac
      [ "$mins" -ge "$SCRATCH_MIN" ] && [ "$mins" -le $(( SCRATCH_MAX_H * 60 )) ] && return 0
      return 1 ;;
    *"day"*)
      [ "$(echo "$created" | grep -oE '^[0-9]+')" -le $(( SCRATCH_MAX_H / 24 )) ] && return 0
      return 1 ;;
    *) return 1 ;;   # weeks / months / years: predates the waves
  esac
}

prune_scratch() {
  # Tagged, locally built, inside the age window, with no container attached.
  docker ps -a --format '{{.Image}}' | sort -u > /tmp/v41-inuse.txt
  docker images --digests --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Digest}}' |
  while IFS=$'\t' read -r rt id created digest; do
    case "$rt" in '<none>:<none>') continue ;; esac
    # a real digest means it was pulled from a registry: not scratch, ever
    case "$digest" in sha256:*) continue ;; esac
    echo "$rt" | grep -qE "$PROTECT" && continue
    # registry-qualified repo (contains a dot or port before the first slash):
    # pulled from somewhere, even if the digest is not recorded locally
    case "${rt%%/*}" in *.*|*:*) continue ;; esac
    in_window "$created" || continue
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
    if [ "$free" -lt "$ALERT" ]; then
      # matches the watcher's notifyOn pattern: this one is worth waking for
      echo "[disk] $(date +%H:%M:%S) free=${free}G below ${ALERT}G ALERT -> pruning"
    else
      # routine: still prunes, but does not match the alert pattern
      echo "[disk] $(date +%H:%M:%S) free=${free}G under ${FLOOR}G floor, reclaiming"
    fi
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
