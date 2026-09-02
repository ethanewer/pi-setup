CC      = gcc
CFLAGS  = -g -O0 -Wall -Wextra -std=c11

all: batchstat

batchstat: batchstat.c tags.c tags.h
	$(CC) $(CFLAGS) -o $@ batchstat.c tags.c

clean:
	rm -f batchstat

.PHONY: all clean
