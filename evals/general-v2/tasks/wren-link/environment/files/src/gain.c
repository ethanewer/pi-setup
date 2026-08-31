// gain.c — Skerry DSP module 1: defines the primitives.
int sk_gain(int x) { return x + 7; }

int sk_mix(int a, int b) { return sk_gain(a) + sk_gain(b); }
