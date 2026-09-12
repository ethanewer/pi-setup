source tests/support/cli.tcl
if {$::singledb} {
    set ::dbnum 0
} else {
    set ::dbnum 9
}


# Hidden case A: a zero-size string key must be reported as the biggest of
# its type even when keys of all the other types are present. Input differs
# from the upstream regression test (which sets exactly one empty string):
# here the empty string coexists with a list, set, hash and zset, and the
# other types' biggest-key lines must stay intact.
start_server {tags {"cli"}} {
    test {bigkeys reports an empty string as biggest string among other types} {
        r flushdb
        r set empty ""
        r rpush list1 a b
        r sadd set1 x
        r hset hash1 f v
        r zadd zset1 1 m

        set cmd [rediscli [srv host] [srv port] [list -n $::dbnum --bigkeys]]
        set result [exec {*}$cmd]

        assert_match {*Sampled 5 keys in the keyspace!*} $result
        assert_match {*Biggest string found "empty" has 0 bytes*} $result
        assert_match {*found "list1" has 2 items*} $result
        assert_match {*found "set1" has 1 members*} $result
        assert_match {*found "hash1" has 1 fields*} $result
        assert_match {*found "zset1" has 1 members*} $result
    }
}