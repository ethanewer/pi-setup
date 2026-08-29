; hidden_ir_a.ll
define i32 @triple(i32 %x) {
entry:
  %m = mul i32 %x, 3
  ret i32 %m
}
