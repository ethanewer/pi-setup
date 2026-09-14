# pennant-caboose hidden case 2 (authored): a consumer group that never read
# anything (no entries_read set) must survive an XSETID ENTRIESADDED
# lowering untouched, while a group that read everything clamps to the new
# counter; the snapshot must stay loadable.
#
# Inputs the upstream regression test does not use: a second group with an
# unset read position on the same stream, 7 entries, trim to 2, counter
# lowered to 2.

start_server {
    tags {"stream"}
} {
    test {ZZHIDDEN never-read: group with no read position survives XSETID ENTRIESADDED lowering untouched} {
        r DEL zhs2
        for {set i 1} {$i <= 7} {incr i} { r XADD zhs2 * f v$i }
        r XGROUP CREATE zhs2 grpfresh 0
        r XGROUP CREATE zhs2 grpread 0
        r XREADGROUP GROUP grpread cr COUNT 7 STREAMS zhs2 ">"
        r XTRIM zhs2 MAXLEN 2
        set top [dict get [r XINFO STREAM zhs2] last-generated-id]
        r XSETID zhs2 $top ENTRIESADDED 2

        foreach ginfo [r XINFO GROUPS zhs2] {
            switch [dict get $ginfo name] {
                grpfresh {
                    assert_equal [dict get $ginfo entries-read] ""
                    assert_equal [dict get $ginfo lag] 2
                }
                grpread {
                    assert_equal [dict get $ginfo entries-read] 2
                    assert_equal [dict get $ginfo lag] 0
                }
            }
        }

        r DEBUG RELOAD
        assert_equal [r XLEN zhs2] 2
        foreach ginfo [r XINFO GROUPS zhs2] {
            switch [dict get $ginfo name] {
                grpfresh { assert_equal [dict get $ginfo entries-read] "" }
                grpread { assert_equal [dict get $ginfo entries-read] 2 }
            }
        }
    }
}