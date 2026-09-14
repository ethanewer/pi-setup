# pennant-caboose hidden case 1 (authored): XSETID ENTRIESADDED lowered all
# the way to 0 on an emptied stream must clamp every consumer group's read
# position to 0 and keep the resulting snapshot loadable.
#
# Inputs the upstream regression test does not use: 15 entries, two groups
# reading different amounts, XTRIM MAXLEN 0 (stream emptied), counter
# lowered to 0.

start_server {
    tags {"stream"}
} {
    test {ZZHIDDEN lower-to-zero: XSETID ENTRIESADDED 0 clamps every group read position and keeps the RDB loadable} {
        r DEL zhs
        for {set i 1} {$i <= 15} {incr i} { r XADD zhs * f v$i }
        r XGROUP CREATE zhs ga 0
        r XGROUP CREATE zhs gb 0
        r XREADGROUP GROUP ga ca COUNT 15 STREAMS zhs ">"
        r XREADGROUP GROUP gb cb COUNT 4 STREAMS zhs ">"
        r XTRIM zhs MAXLEN 0
        set top [dict get [r XINFO STREAM zhs] last-generated-id]
        r XSETID zhs $top ENTRIESADDED 0

        foreach ginfo [r XINFO GROUPS zhs] {
            set name [dict get $ginfo name]
            if {$name eq "ga" || $name eq "gb"} {
                assert_equal [dict get $ginfo entries-read] 0
                assert_equal [dict get $ginfo lag] 0
            }
        }

        r DEBUG RELOAD
        assert_equal [r XLEN zhs] 0
        foreach ginfo [r XINFO GROUPS zhs] {
            set name [dict get $ginfo name]
            if {$name eq "ga" || $name eq "gb"} {
                assert_equal [dict get $ginfo entries-read] 0
                assert_equal [dict get $ginfo lag] 0
            }
        }
    }
}