; ModuleID = 'seq1'
target triple = "x86_64-unknown-linux-gnu"

; a_seq(x) = x + 5
define i32 @a_seq(i32 %x) {
entry:
  %s = add nsw i32 %x, 5
  ret i32 %s
}
