CC = gcc
CFLAGS = -g -O0 -Wall -Wextra -std=c11

memledger: ledger.c util.c util.h
	$(CC) $(CFLAGS) -o memledger ledger.c util.c

clean:
	rm -f memledger

.PHONY: clean
