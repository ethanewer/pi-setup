/app/asm.txt contains two x86-32 procedure bodies labelled FUNC1 and FUNC2. Each takes two 4-byte arguments. In x86 calling conventions, the difference between `cdecl` and `stdcall` is who removes the arguments from the stack after the call:

- `cdecl`: caller pops the arguments after the call returns; the callee ends with a bare `ret`.
- `stdcall`: the callee pops its own arguments; the callee ends with `ret N` where N is the total argument size in bytes.

Read `/app/asm.txt`, look at the final instruction of each function body:

- FUNC1 ends with `ret` (no number).
- FUNC2 ends with `ret 8`.

Write `/app/answer.json` with exactly these fields:

```json
{
  "func1": "cdecl",
  "func2": "stdcall",
  "stack_cleaner_func1": "caller",
  "stack_cleaner_func2": "callee"
}
```

Fill the string values as the correct calling-convention analysis: for each function state whether it is `cdecl` or `stdcall`, and whether the `caller` or the `callee` is responsible for cleaning the stack. Use only lowercase values from {`cdecl`, `stdcall`, `caller`, `callee`}.