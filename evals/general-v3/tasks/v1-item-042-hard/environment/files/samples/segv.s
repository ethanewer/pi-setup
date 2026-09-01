# Hidden (hard): deliberately fault on an out-of-memory load.
        li      $t0, 0xFFFF0000
        lw      $t1, 0($t0)
        li      $v0, 4001
        move    $a0, $zero
        syscall
