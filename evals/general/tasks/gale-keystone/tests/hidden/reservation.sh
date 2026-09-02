#!/usr/bin/env bash
# Hidden case 2: re-run the reservation tool for a genuinely different venue
# and company; the pair and its confirmation must land in reservations.json.
set -u
VENUE="Glacier Indoor Bowl"
COMPANY="Nimbus Marine Ltd"

python3 /app/reserve.py --venue "$VENUE" --company "$COMPANY" >/tmp/rsv.out 2>/tmp/rsv.err
rc=$?
[ "$rc" = 0 ] || { echo "hidden-reservation: reserve.py exited $rc: $(cat /tmp/rsv.err)"; exit 1; }

CONF=$(head -n1 /tmp/rsv.out)
grep -q '"venue": "Glacier Indoor Bowl"' /app/reservations.json || { echo "hidden-reservation: venue not recorded"; exit 1; }
grep -q '"company": "Nimbus Marine Ltd"' /app/reservations.json || { echo "hidden-reservation: company not recorded"; exit 1; }
case "$CONF" in
  HARBOR-*) ;;
  *) echo "hidden-reservation: bad confirmation '$CONF'"; exit 1 ;;
esac
grep -q "\"confirmation\": \"$CONF\"" /app/reservations.json || { echo "hidden-reservation: confirmation not recorded"; exit 1; }

# the visible reservation must still be present
grep -q '"venue": "Woodbank Pavilion"' /app/reservations.json || { echo "hidden-reservation: earlier reservation lost"; exit 1; }

echo "hidden-reservation: $CONF recorded for $VENUE / $COMPANY"
exit 0