; hidden_ir_b.ll
declare i32 @triple(i32)

define i32 @alt_run(i32 %v) {
entry:
  %r = call i32 @triple(i32 %v)
  %r2 = add i32 %r, 1
  ret i32 %r2
}
