; ModuleID = 'trim'
target triple = "x86_64-unknown-linux-gnu"

declare i32 @vc_base(i32)

; vc_trim(x) = vc_base(x) - 2  (cross-module call)
define i32 @vc_trim(i32 %x) {
entry:
  %b = call i32 @vc_base(i32 %x)
  %t = sub nsw i32 %b, 2
  ret i32 %t
}
