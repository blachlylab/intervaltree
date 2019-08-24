CC=gcc
CFLAGS=-O3

%.o: %.c %.h
	$(CC) -c -o $@ $< $(CFLAGS)
