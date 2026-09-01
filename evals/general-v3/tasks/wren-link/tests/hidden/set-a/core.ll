; ModuleID = 'core'
target triple = "x86_64-unknown-linux-gnu"

; vc_base(x) = x * 4
define i32 @vc_base(i32 %x) {
entry:
  %m = mul nsw i32 %x, 4
  ret i32 %m
}
