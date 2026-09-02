// limiter.c — Skerry DSP module 3: declares both earlier functions.
int sk_gain(int x);
int sk_shape(int x);

// sk_limit(x) = sk_shape(x) - sk_gain(x) = (x + 7) * 2 - (x + 7) = x + 7
int sk_limit(int x) { return sk_shape(x) - sk_gain(x); }
