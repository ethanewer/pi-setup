# Hidden (main): read one ASCII digit from stdin, sum 1..n, print decimal.
        addiu   $sp, $sp, -16
        li      $v0, 4003
        li      $a0, 0
        move    $a1, $sp
        li      $a2, 1
        syscall
        lbu     $t0, 0($sp)
        addiu   $t0, $t0, -48
        li      $t1, 0
        li      $t2, 1
top:
        blez    $t0, out
        add     $t1, $t1, $t2
        addiu   $t2, $t2, 1
        addiu   $t0, $t0, -1
        j       top
out:
        move    $s0, $t1
        addiu   $sp, $sp, -16
        move    $t2, $sp
        li      $t5, 10
conv:
        divu    $s0, $t5
        mflo    $t6
        mfhi    $t7
        addiu   $t7, $t7, 48
        sb      $t7, 0($t2)
        addiu   $t2, $t2, 1
        move    $s0, $t6
        bne     $s0, $zero, conv
        addiu   $t8, $sp, -16
        move    $t3, $t8
        li      $t9, 0
rev:
        addiu   $t2, $t2, -1
        lbu     $t1, 0($t2)
        sb      $t1, 0($t3)
        addiu   $t3, $t3, 1
        addiu   $t9, $t9, 1
        sltu    $t1, $sp, $t2
        bne     $t1, $zero, rev
        li      $t1, 10
        sb      $t1, 0($t3)
        addiu   $t9, $t9, 1
        li      $v0, 4004
        li      $a0, 1
        move    $a1, $t8
        move    $a2, $t9
        syscall
        li      $v0, 4001
        move    $a0, $zero
        syscall
