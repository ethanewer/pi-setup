# Rust: read and trace a small loop

`/app/main.rs` contains a short Rust program:

```rust
fn main() {
    let mut total = 0;
    for i in 1..6 {
        total += i * i;
    }
    println!("{}", total);
}
```

In Rust, the range operator `a..b` produces the integers `a, a+1, ..., b-1`
(up to but **not** including `b`).

Determine the exact integer that `println!("{}", total)` prints when the
program runs (trace the loop by hand — no Rust toolchain is required): the
loop variable `i` takes each value in `1,2,3,4,5`, and `total` accumulates the
sum of `i*i` for each of those values.

Write **only** that integer (a base-10 whole number, no quotes, no trailing
text) to `/app/answer.txt`.

So for example, if the printed value were `42`, `/app/answer.txt` would contain
exactly the two characters `42` (no newline required, but one is harmless).