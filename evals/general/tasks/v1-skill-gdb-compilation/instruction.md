You need to use **gdb** on a **compiled with debug symbols** C program to inspect a runtime variable.

In `/app` there is `/app/debug.c`:

```c
#include <stdio.h>
int mix(int a, int b, int c){
    int r = a*3 + b - c;
    return r;
}
int main(void){
    int x1 = 7;
    int x2 = 2;
    int base = mix(x1, x2, 5);
    int checksum = (base * 4) + (x1 % x2) - ((base >> 1) & 0xF);
    printf("hid=%d\n", checksum);
    return 0;
}
```

Compile it with debug info: `gcc -g -O0 /app/debug.c -o /app/debug_bin`.

Use **gdb** to set a breakpoint on the line that computes `checksum` (or on `main`), run the program, and **print the value of the `checksum` variable** at that stop point.

Write the value as a JSON object to `/app/debugged.json`:
```json
{"checksum": <integer value of checksum at runtime>}
```

Run your debug session so `/app/debugged.json` contains the correct runtime value of `checksum`. `gcc` and `gdb` are installed.