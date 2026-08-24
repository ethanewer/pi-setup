// main.rs — a short Rust program for the probe exercise.
fn main() {
    let mut total = 0;
    for i in 1..6 {
        total += i * i;
    }
    println!("{}", total);
}