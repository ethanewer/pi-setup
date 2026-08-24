# Projectile simulation (Euler integration)

Simulate a 2-D projectile with **linear (velocity-proportional) drag** using
**Euler integration**, exactly as specified below. Write your simulation as a
Python script.

**Algorithm (implement this exactly):**

```
x = 0.0; y = 0.0; vx = 50.0; vy = 60.0
g = 9.81; k = 0.05; dt = 0.1
while True:
    vx = vx + (-k * vx) * dt
    vy = vy + (-g - k * vy) * dt
    x  = x  + vx * dt
    y  = y  + vy * dt
    if y < 0.0:
        break
```

(`x` and `y` are the projected position, `vx`/`vy` the velocities; the loop stops at
the **first step where `y < 0`** — i.e. the impact step. Use float arithmetic, not
any numeric approximation.)

Write the value of `x` at that impact step to `/app/result.txt`, rounded exactly to
**3 decimal places** (e.g. `424.593`), followed by a newline.

When done, confirm `/app/result.txt` exists and contains the rounded value.