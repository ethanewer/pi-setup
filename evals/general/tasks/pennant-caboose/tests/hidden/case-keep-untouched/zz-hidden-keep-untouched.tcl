# pennant-caboose hidden case 3 (authored): lowering ENTRIESADDED must clamp
# only the groups whose read position exceeds the new counter; a group that
# has read less than the new counter must be left exactly as it was, and the
# snapshot must stay loadable.
#
# Inputs the upstream regression test does not use: 8 entries, two groups at
# different read positions (8 and 2), trim to 3, counter lowered from 8 to 5
# (so one group clamps, the other is untouched).

start_server {
    tags {"stream"}
} {
    test {ZZHIDDEN keep-untouched: lowering ENTRIESADDED clamps only the groups above the new counter} {
        r DEL zhs3
        for {set i 1} {$i <= 8} {incr i} { r XADD zhs3 * f v$i }
        r XGROUP CREATE zhs3 ga 0
        r XGROUP CREATE zhs3 gb 0
        r XREADGROUP GROUP ga ca COUNT 8 STREAMS zhs3 ">"
        r XREADGROUP GROUP gb cb COUNT 2 STREAMS zhs3 ">"
        r XTRIM zhs3 MAXLEN 3
        set top [dict get [r XINFO STREAM zhs3] last-generated-id]
        r XSETID zhs3 $top ENTRIESADDED 5

        foreach ginfo [r XINFO GROUPS zhs3] {
            switch [dict get $ginfo name] {
                ga {
                    assert_equal [dict get $ginfo entries-read] 5
                    assert_equal [dict get $ginfo lag] 0
                }
                gb {
                    assert_equal [dict get $ginfo entries-read] 2
                    assert_equal [dict get $ginfo lag] 3
                }
            }
        }

        r DEBUG RELOAD
        assert_equal [r XLEN zhs3] 3
        foreach ginfo [r XINFO GROUPS zhs3] {
            switch [dict get $ginfo name] {
                ga { assert_equal [dict get $ginfo entries-read] 5 }
                gb { assert_equal [dict get $ginfo entries-read] 2 }
            }
        }
    }
}