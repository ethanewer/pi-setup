# Sample program: sum of 1..10 = 55, print decimal, exit 0.
# Exercises: li,add,addiu,slti,beq,j,lw,sw,divu,mflo,mfhi,sb,lbu,subu,
#            sltu,addu(li),syscall write/exit.
.set N, 10

        li      $t0, 0          # sum
        li      $t1, 1          # loop counter
loop:
        slti    $t2, $t1, 11
        beq     $t2, $zero, done
        add     $t0, $t0, $t1
        addiu   $t1, $t1, 1
        j       loop
done:
        addiu   $sp, $sp, -32
        sw      $t0, 0($sp)
        lw      $t4, 0($sp)     # reload value (lw/sw path)
        move    $t2, $sp        # reversed-digit cursor
        li      $t5, 10
conv:
        divu    $t4, $t5
        mflo    $t6
        mfhi    $t7
        addiu   $t7, $t7, 48
        sb      $t7, 0($t2)
        addiu   $t2, $t2, 1
        move    $t4, $t6
        bne     $t4, $zero, conv
        addiu   $t8, $sp, -16   # out buffer
        move    $t3, $t8        # out cursor
        li      $t9, 0          # byte count
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
