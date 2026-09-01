CC      = gcc
CFLAGS  = -O2 -Wall -Wextra

forgebench: main.c forge.c
	$(CC) $(CFLAGS) -o forgebench main.c forge.c

clean:
	rm -f forgebench

.PHONY: clean
