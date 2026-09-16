source tests/support/cli.tcl
if {$::singledb} {
    set ::dbnum 0
} else {
    set ::dbnum 9
}


# Hidden case C: the --keystats command (a different keyspace-scanning mode
# that shares the same per-type biggest-key bookkeeping through
# updateKeyType()) must report a zero-length string in its "Top length and
# cardinality per type" section. The upstream regression test only drives
# --bigkeys; this case would still fail on a fix that patched only the
# --bigkeys path, because updateKeyType() is used exclusively by --keystats.
start_server {tags {"cli"}} {
    test {keystats reports a zero-length string in the length report} {
        r flushdb
        r set empty ""

        set cmd [rediscli [srv host] [srv port] [list -n $::dbnum --keystats]]
        set result [exec {*}$cmd]

        assert_match {*--- Top size per type ---*} $result
        assert_match {*"empty" is *} $result
        assert_match {*--- Top length and cardinality per type ---*} $result
        assert_match {*"empty" has 0B*} $result
    }
}