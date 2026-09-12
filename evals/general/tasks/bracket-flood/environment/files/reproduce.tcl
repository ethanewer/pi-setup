#!/usr/bin/env tclsh
# bracket-flood reproducer (Tcl). Expects a redis server on $env(PORT);
# run via /app/reproduce.sh. Uses the project's own Tcl client library.
source /app/src/tests/support/redis.tcl
set r [redis 127.0.0.1 $env(PORT)]

$r del repro-key
$r set repro-key "repro-value"
set enc [$r dump repro-key]
$r del repro-key

regexp {expired_keys:(\d+)} [$r info stats] -> ek_before

puts "== oversized relative TTL on RESTORE =="
puts "key exists before restore: [$r exists repro-key]"
set rc [catch {$r restore repro-key 9223372036854775807 $enc} rep]
puts "restore result: caught=$rc reply=\"$rep\""
regexp {expired_keys:(\d+)} [$r info stats] -> ek_after
puts "key exists after restore:  [$r exists repro-key]"
puts "server expired_keys: before=$ek_before after=$ek_after"

# Secondary probe: the same restore against an EXISTING key with REPLACE.
$r set repro-key "old-value"
set rc2 [catch {$r restore repro-key 9223372036854775807 $enc replace} rep2]
puts "restore (replace, existing key): caught=$rc2 reply=\"$rep2\""
regexp {expired_keys:(\d+)} [$r info stats] -> ek2
puts "value still readable after: [$r get repro-key]"
puts "expired_keys now: $ek2 (before first probe: $ek_before)"

puts "== at the current tree state you should see restore succeed (caught=0),"
puts "   then the freshly restored key silently vanishes and expired_keys"
puts "   increments. A correct tree refuses with an 'invalid expire time'"
puts "   error (caught=1) and leaves the keys and the counter untouched. =="