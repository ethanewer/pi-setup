; ModuleID = 'seq2'
target triple = "x86_64-unknown-linux-gnu"

declare i32 @a_seq(i32)

; b_seq(x) = a_seq(x) * 3
define i32 @b_seq(i32 %x) {
entry:
  %a = call i32 @a_seq(i32 %x)
  %m = mul nsw i32 %a, 3
  ret i32 %m
}
