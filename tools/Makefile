
# makefile for serial tool
CC = gcc
CFLAGS = -O0 -Wall

all: serialtool

serialtool: serialtool.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f serialtool
