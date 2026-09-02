; ModuleID = 'seq3'
target triple = "x86_64-unknown-linux-gnu"

declare i32 @a_seq(i32)
declare i32 @b_seq(i32)

; c_seq(x) = b_seq(x) + a_seq(x)  (two distinct cross-module calls)
define i32 @c_seq(i32 %x) {
entry:
  %b = call i32 @b_seq(i32 %x)
  %a = call i32 @a_seq(i32 %x)
  %s = add nsw i32 %b, %a
  ret i32 %s
}
