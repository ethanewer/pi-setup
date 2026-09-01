CC      = gcc
CFLAGS  = -g -O0 -Wall -Wextra -std=c11

all: kvcat

kvcat: fixed.c tokens.c tokens.h
	$(CC) $(CFLAGS) -o $@ fixed.c tokens.c

clean:
	rm -f kvcat

.PHONY: all clean
