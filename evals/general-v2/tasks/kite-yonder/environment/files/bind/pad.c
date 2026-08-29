/* pad.c -- tiny native function used by the Python <-> C ctypes binding.
 * Fills the caller's byte buffer with a deterministic byte pattern and returns
 * the number of bytes actually written (never more than `cap`). */
#include <stdio.h>

long bind_pad(unsigned char *buf, int cap, int n){
    if(cap <= 0) return 0;
    int m = n < cap ? n : cap;
    for(int i = 0; i < m; i++) buf[i] = (unsigned char)((i * 37 + 11) & 0xff);
    for(int i = m; i < cap; i++) buf[i] = 0;
    return (long)m;
}