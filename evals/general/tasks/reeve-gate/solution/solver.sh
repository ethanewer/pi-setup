#!/bin/bash
# reeve-gate solver: data-driven account and privilege state engine.
#
# Usage: setup_accounts.sh <scenario.json>
#
# Reads a scenario JSON describing groups, users (memberships, password state,
# aging, expiry, homes) and filesystem paths with ownership and mode bits, and
# brings the live system to exactly that state using the built shadow
# account-management tools only. Account databases are never hand-edited.
#
# The engine is idempotent: if a scenario account already exists (e.g. the
# agent is iterating), it removes it first and rebuilds it from the scenario.
set -euo pipefail

SCENARIO="${1:?usage: setup_accounts.sh <scenario.json>}"
[ -f "$SCENARIO" ] || { echo "scenario not found: $SCENARIO" >&2; exit 2; }

USERADD=/usr/sbin/useradd
USERMOD=/usr/sbin/usermod
USERDEL=/usr/sbin/userdel
GROUPADD=/usr/sbin/groupadd
GROUPDEL=/usr/sbin/groupdel
CHPASSWD=/usr/sbin/chpasswd
PASSWD=/usr/bin/passwd
CHAGE=/usr/bin/chage

# ---------- 1. remove leftover copies of the scenario's accounts ----------
while IFS=$'\t' read -r name _; do
    [ -n "$name" ] || continue
    if getent passwd "$name" >/dev/null 2>&1; then
        "$USERDEL" -r "$name" || true
    fi
done < <(jq -r '.users[]? | [.name, ""] | @tsv' "$SCENARIO")

while IFS=$'\t' read -r gname; do
    [ -n "$gname" ] || continue
    if getent group "$gname" >/dev/null 2>&1; then
        "$GROUPDEL" "$gname" || true
    fi
done < <(jq -r '.groups[]? | .name' "$SCENARIO")

# ---------- 2. groups first, so users can reference them ----------
while IFS=$'\t' read -r gname gid; do
    [ -n "$gname" ] || continue
    "$GROUPADD" -g "$gid" "$gname"
done < <(jq -r '.groups[]? | [.name, .gid] | @tsv' "$SCENARIO")

# ---------- 3. users ----------
while IFS=$'\037' read -r name uid pgroup sup home createhm shell gecos; do
    [ -n "$name" ] || continue
    args=(-u "$uid" -g "$pgroup" -s "$shell" -c "$gecos" -d "$home")
    if [ "$createhm" = "true" ]; then args+=(-m); else args+=(-M); fi
    if [ "$sup" != "-" ]; then args+=(-G "$sup"); fi
    "$USERADD" "${args[@]}" "$name"
done < <(jq -r '.users[]? | [.name, .uid, .primary_group,
         (if (.supplementary_groups | length) > 0 then .supplementary_groups | join(",") else "-" end),
         .home, (.create_home | tostring), .shell, .gecos] | @tsv' "$SCENARIO" | tr '\t' '\037')

# ---------- 4. password state, lock state, aging, expiry ----------
while IFS=$'\037' read -r name pw locked mindays maxdays warndays inactive expiry; do
    [ -n "$name" ] || continue
    if [ "$pw" != "-" ]; then
        printf '%s:%s\n' "$name" "$pw" | "$CHPASSWD" -c SHA512
    fi
    # lock state: only touch when it differs from what the scenario wants
    cur="$(getent shadow "$name" | cut -d: -f2)"
    case "$cur" in
        '!'*) cur_locked=true ;;
        *)    cur_locked=false ;;
    esac
    if [ "$locked" = "true" ] && [ "$cur_locked" = "false" ]; then
        "$PASSWD" -l "$name"
    elif [ "$locked" = "false" ] && [ "$cur_locked" = "true" ]; then
        "$PASSWD" -u "$name"
    fi
    [ "$mindays"  != "null" ] && "$CHAGE" -m "$mindays"  "$name"
    [ "$maxdays"  != "null" ] && "$CHAGE" -M "$maxdays"  "$name"
    [ "$warndays" != "null" ] && "$CHAGE" -W "$warndays" "$name"
    [ "$inactive" != "null" ] && "$CHAGE" -I "$inactive" "$name"
    if [ "$expiry" != "null" ] && [ -n "$expiry" ]; then
        "$USERMOD" -e "$expiry" "$name"
    fi
done < <(jq -r '.users[]? | [.name, (if .password? then .password else "-" end),
         (.locked | tostring), (.min_days // "null"), (.max_days // "null"),
         (.warn_days // "null"), (.inactive_days // "null"),
         (if .expiry? then .expiry else "null" end)] | @tsv' "$SCENARIO" | tr '\t' '\037')

# ---------- 5. home directory modes ----------
while IFS=$'\037' read -r name home mode; do
    [ -n "$name" ] || continue
    [ "$mode" = "null" ] && continue
    [ -d "$home" ] || continue
    chmod "$mode" "$home"
done < <(jq -r '.users[]? | [.name, .home, (.home_mode // "null")] | @tsv' "$SCENARIO" | tr '\t' '\037')

# ---------- 6. paths and marker files ----------
while IFS=$'\037' read -r path kind mode owner group mfile mcontent mmode mowner mgroup; do
    [ -n "$path" ] || continue
    if [ "$kind" = "directory" ]; then
        mkdir -p "$path"
        chown "$owner:$group" "$path"
        chmod "$mode" "$path"
    fi
    if [ -n "$mfile" ] && [ "$mfile" != "-" ]; then
        mo="${mowner:-$owner}"
        mg="${mgroup:-$group}"
        printf '%s' "$mcontent" > "$path/$mfile"
        chown "$mo:$mg" "$path/$mfile"
        chmod "${mmode:-0640}" "$path/$mfile"
    fi
done < <(jq -r '.paths[]? | [.path, (.kind // "directory"), .mode, .owner, .group,
         (if .marker? then .marker.file else "-" end),
         (.marker.content // ""), (.marker.mode // ""),
         (.marker.owner // ""), (.marker.group // "")] | @tsv' "$SCENARIO" | tr '\t' '\037')

echo "== applied $SCENARIO =="
jq -r '.users[]? | .name' "$SCENARIO" | sort -u | sed 's/^/account: /'
exit 0