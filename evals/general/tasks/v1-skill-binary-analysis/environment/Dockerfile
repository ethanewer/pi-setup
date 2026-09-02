FROM bench-base:ubuntu-24.04
WORKDIR /app
RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*
RUN printf '%s\n' '#include <stdio.h>' '#include <string.h>' 'int main(int argc, char **argv){' '  if(argc != 2){ puts("DENIED"); return 1; }' '  if(strcmp(argv[1], "T0ken-Xc7QpR9") != 0){ puts("DENIED"); return 1; }' '  puts("ALLOWED");' '  return 0;' '}' > /tmp/passcheck.c && gcc -O0 -o /app/passcheck /tmp/passcheck.c && rm -f /tmp/passcheck.c
