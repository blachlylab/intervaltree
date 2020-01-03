CC=gcc
CFLAGS=-O3 $(INSTRUMENT)
#INSTRUMENT=-DINSTRUMENT

.PHONY: clean

all:	source/cgranges.o

clean:
	rm source/cgranges.o

%.o: %.c %.h
	$(CC) -c -o $@ $< $(CFLAGS)
