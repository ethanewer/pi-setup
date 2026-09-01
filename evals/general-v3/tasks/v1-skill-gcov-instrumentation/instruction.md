You are asked to use **gcov**, GCC's instrumented coverage tool, to measure the coverage of a program file.

In `/app` there is a C source file `/app/program.c`:

```c
#include <stdio.h>
int helper(int x){
    int r = x * 2;
    return r;
}
int main(void){
    int t = helper(1);
    t = helper(3);
    printf("t=%d\n", t);
    if (t > 100) {
        printf("big\n");
    }
    return 0;
}
```

And a build file `/app/Makefile` that compiles it with gcov instrumentation and runs it:

```makefile
run:
	gcc -ftest-coverage -fprofile-arcs program.c -o program
	./program
	gcov program.c
```

Do the following:
1. Run the build (e.g. `make --directory=/app run`) so that `/app/program.c.gcov` is generated.
2. When the build runs `gcov`, it prints a **line coverage summary line** of the form
   `Lines executed:X.X% of Y` to its output. Capture gcov's summary and extract
the line coverage percentage (percent) from that line.
3. Write `/app/coverage.json` containing exactly:
   ```json
   {"coverage_percent": <float rounded to 1 decimal>}
   ```

The correct percentage is **not** 100%, because the `t > 100` = true branch is never executed at runtime. Produce `/app/coverage.json` with the correct value. `gcc` and `gcov` are installed.