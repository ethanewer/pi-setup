/* beta.c -- ring-math helper, translation unit 2. */
double beta_quant(double x, double eps){
    double s = x * x + eps;
    return (s > 0 ? (x > 0 ? 1.0 : -1.0) : 0.0) * (s < 0 ? s * s : s);
}
long beta_bucket(char c){ return (long)(c == 'x' ? 7 : (c - ' ')); }