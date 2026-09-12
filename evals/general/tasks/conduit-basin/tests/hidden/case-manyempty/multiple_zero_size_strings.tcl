source tests/support/cli.tcl
if {$::singledb} {
    set ::dbnum 0
} else {
    set ::dbnum 9
}


# Hidden case B: several ALL-empty strings. The bug must not require a
# single-key database to show: with three empty strings the scan counts
# "3 strings ... with 0 bytes" and must still name exactly one of them as
# the biggest string (0 bytes). The key name is not asserted literally
# because SCAN order is not deterministic across server instances; instead
# exactly one biggest-string line must appear and its name must be one of
# the keys we created. Fails at the buggy snapshot (no biggest-string line
# at all).
start_server {tags {"cli"}} {
    test {bigkeys reports one of several zero-size strings as biggest string} {
        r flushdb
        r set one ""
        r set two ""
        r set three ""

        set cmd [rediscli [srv host] [srv port] [list -n $::dbnum --bigkeys]]
        set result [exec {*}$cmd]

        assert_match {*3 strings with 0 bytes (100.00% of keys, avg size 0.00)*} $result

        set lines [split $result "\n"]
        set biggest [lsearch -all -inline $lines "*Biggest string found * has 0 bytes*"]
        assert_equal 1 [llength $biggest]

        set line [lindex $biggest 0]
        if {![regexp {Biggest string found "([^"]+)" has 0 bytes} $line -> name]} {
            fail "biggest-string line does not parse: $line"
        }
        set idx [lsearch -exact {one two three} $name]
        assert {$idx >= 0}
    }
}