# Fitting a bounded random-walk sampler

Deliver one **Python program** at `/app/sample.py`: a bounded random-walk
Metropolis sampler for a truncated normal, driven by a config file. It must be a
real general sampler, not a one-off for the sample config, because the verifier
runs it on fresh configs under `/tests/hidden`.

## Distribution to sample

The target is proportional to

```
f(x) ∝ exp( -(x - center)^2 / (2 * scale) )    for  x in [active_support]
       0                                       otherwise
```

where `center` is the mode and `scale` is the **variance** of the untruncated
Gaussian (`scale > 0`). Sampling is performed over the bounded domain
`[support.lo, support.hi]`: any proposed state outside those bounds is
rejected (never accepted). Because the domain is bounded, the sampled
distribution is the **truncated** normal — its mean and variance differ from
`center`/`scale` when truncation matters.

## The config file

The program reads a plain text config. The visible input `/app/target.txt`
looks like:

```
support=-4,4
center=1.25
scale=2.4
n=12000
burn_in=1000
seed=812
```

Keys and their meaning:

| key | meaning |
|---|---|
| `support` | `lo,hi` bounds of the domain (floats, `lo < hi`) |
| `center` | Gaussian centre / mode (float) |
| `scale` | variance of the untruncated normal (positive float) |
| `n` | number of **retained** draws to write (positive int) |
| `burn_in` | integer warm-up draws to discard before retention |
| `seed` | RNG seed: identical config + seed ⇒ identical output |

Config files may contain blank lines and `#` comments; parsing must ignore both.
Keys appear exactly once.

## Program interface

```
python3 /app/sample.py [CONFIG] [OUT]
```

- `CONFIG` — path to the config file. **Default `/app/target.txt`.**
- `OUT` — path to write the retained samples. **Default `/app/samples.txt`.**
- With no arguments it must read `/app/target.txt` and write `/app/samples.txt`.

It writes exactly `n` lines, one sample per line (e.g. `%.6f` formatting), then
terminates with exit code 0. It is a self-contained Python file using only the
standard library — `random.Random` seeded with `seed` is the expected driver.

## Requirements / edge cases the verifier probes

- **Discard burn-in**: write exactly `n` retained draws; the `burn_in` warm-up
  draws must be dropped and must not appear in the output.
- **Support enforced**: every retained sample is within `[support.lo,
  support.hi]`; no proposed jump may be accepted outside the domain.
- **Shape correctness**: the sample mean and variance must match the **truncated**
  normal on the given `support`, not the untruncated Gaussian. This is probed
  with a config where the support is narrow relative to `scale` so truncation
  strongly shifts the moments away from `center`/`scale`.
- **Real sampling**: draws must be statistically representative (a uniform or
  ad-hoc distribution on `support` will fail the moment checks).
- **Reproducibility**: running the same `CONFIG` twice yields byte-identical
  output (any new RNG sample).
- **Generality**: must work for arbitrary positive `scale`, arbitrary
  `center`, arbitrary `lo < hi`, and arbitrary positive `n`, `burn_in`, `seed`.
- **Robustness**: handle blank lines and `#` comment lines in the config.

## Inputs must not be modified

`/app/target.txt` is an **input**; do not alter it. The verifier checks that its
contents are unchanged. Do not modify any other files under `/app`.

## Deliverables

- `/app/sample.py` — the sampler (must exist and be runnable).
- `/app/samples.txt` — the visible-case output produced by running your program
  with no arguments, read back and checked.

Your program must also run on the hidden configs provided by the verifier, so
implement everything as a general tool driven by the documented config format.