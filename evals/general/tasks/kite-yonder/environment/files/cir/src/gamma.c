/* gamma.c -- ring-math helper, translation unit 3. */
double gamma_sep(double a, double b){ return a > b ? a - b : b - a; }
int gamma_sign(long v){ return (v > 0) - (v < 0); }