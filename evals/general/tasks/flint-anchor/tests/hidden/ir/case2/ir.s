.file "ir2.s"
.text
.globl main
.type main, @function
main:
    pushq %rbp
    movq  %rsp, %rbp
    movq  $9, %rdi
    call  core_double@PLT
    movl  %eax, %esi
    leaq  .LC0(%rip), %rdi
    movl  $0, %eax
    call  printf@PLT
    movl  $0, %eax
    popq  %rbp
    ret
.size main, .-main
.section .rodata
.LC0: .string "%d\n"
.section .note.GNU-stack,"",@progbits
