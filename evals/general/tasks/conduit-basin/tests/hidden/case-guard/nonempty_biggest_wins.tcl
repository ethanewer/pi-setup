source tests/support/cli.tcl
if {$::singledb} {
    set ::dbnum 0
} else {
    set ::dbnum 9
}


# Hidden case D: a zero-size key must never shadow a larger key of the same
# type. The empty string key 'z' coexists with the 5-byte key 'big'; the
# biggest-string line must name 'big' with 5 bytes regardless of SCAN order
# (a correct fix records the first key of a type and only replaces it with a
# strictly larger one). Also guards the totals: 2 strings, 5 bytes total.
# (This case also passes on the untouched buggy tree; it exists to reject
# sloppy candidate fixes such as a blanket '>=' that lets the empty key
# win whenever it is scanned after a larger key.)
start_server {tags {"cli"}} {
    test {bigkeys: a larger string stays biggest when an empty string is present} {
        r flushdb
        r set big "hello"
        r set z ""

        set cmd [rediscli [srv host] [srv port] [list -n $::dbnum --bigkeys]]
        set result [exec {*}$cmd]

        assert_match {*Sampled 2 keys in the keyspace!*} $result
        assert_match {*Biggest string found "big" has 5 bytes*} $result
        assert_match {*2 strings with 5 bytes*} $result
    }
}