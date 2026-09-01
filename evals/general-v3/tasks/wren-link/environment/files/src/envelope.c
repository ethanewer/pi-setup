// envelope.c — Skerry DSP module 2: declares sk_gain (cross-module reference).
int sk_gain(int x);

// shape(x) = ((x + 7) * 2) via the cross-module call
int sk_shape(int x) { return sk_gain(x) * 2; }
