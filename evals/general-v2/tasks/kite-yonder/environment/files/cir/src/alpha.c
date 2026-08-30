/* alpha.c -- ring-math helper, translation unit 1. */
double ring_radius_r(double r, double phi){ return r * (1.0 + 0.25 * phi); }
int led_count(int layers, int stride){ return layers * stride + 1; }
long kday_shift(long base, long salt){ return base + (salt * 2654435761UL); }