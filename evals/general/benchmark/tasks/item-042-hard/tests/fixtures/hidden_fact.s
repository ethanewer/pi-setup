# Hidden (hard): read an ASCII integer from stdin ('6\n'), parse it, compute
# factorial recursively, print decimal, exit 0.
        addiu   $sp, $sp, -32
        li      $v0, 4003
        li      $a0, 0
        move    $a1, $sp
        li      $a2, 8
        syscall
        move    $t0, $zero      # value
        move    $t1, $sp        # cursor
        li      $t2, 10
par:
        lbu     $t3, 0($t1)
        addiu   $t4, $t3, -48
        slti    $t5, $t4, 0
        bne     $t5, $zero, done_parse
        slti    $t5, $t4, 10
        beq     $t5, $zero, done_parse
        mult    $t0, $t2
        mflo    $t0
        add     $t0, $t0, $t4
        addiu   $t1, $t1, 1
        j       par
done_parse:
        move    $a0, $t0
        jal     fact
        move    $s0, $v0
        addiu   $sp, $sp, -32
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

fact:
        addiu   $sp, $sp, -8
        sw      $ra, 4($sp)
        sw      $a0, 0($sp)
        blez    $a0, base
        addiu   $a0, $a0, -1
        jal     fact
        lw      $t0, 0($sp)
        mult    $t0, $v0
        mflo    $v0
        j       ret
base:
        li      $v0, 1
ret:
        lw      $ra, 4($sp)
        addiu   $sp, $sp, 8
        jr      $ra

segv_only:
        li      $t0, 0xFFFF0000
        lw      $t1, 0($t0)
        li      $v0, 4001
        move    $a0, $zero
        syscall
