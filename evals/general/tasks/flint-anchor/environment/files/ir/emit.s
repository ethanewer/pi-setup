# flint emitted IR for the visible default build.
# main calls core_answer(5), prints its int result as a decimal, exits 0.
.file "emit.s"
.text
.globl main
.type main, @function
main:
    pushq %rbp
    movq  %rsp, %rbp
    movq  $5, %rdi              # argument n = 5
    call  core_answer@PLT
    movl  %eax, %esi            # printf's second argument
    leaq  .LC0(%rip), %rdi
    movl  $0, %eax
    call  printf@PLT
    movl  $0, %eax
    popq  %rbp
    ret
.size main, .-main
.section .rodata
.LC0:
    .string "%d\n"
.section .note.GNU-stack,"",@progbits
