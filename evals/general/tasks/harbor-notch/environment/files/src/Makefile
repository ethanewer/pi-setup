CC = gcc
CFLAGS = -g -O0 -Wall -Wextra -std=c11

mtally: mtally.c store.c store.h
	$(CC) $(CFLAGS) -o mtally mtally.c store.c

clean:
	rm -f mtally

.PHONY: clean
