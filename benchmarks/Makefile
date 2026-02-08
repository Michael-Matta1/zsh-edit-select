# Makefile for benchmark tools

CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=c99

all: x11-benchmark wayland-benchmark

x11-benchmark: x11-benchmark.c
	$(CC) $(CFLAGS) -o x11-benchmark x11-benchmark.c

wayland-benchmark: wayland-benchmark.c
	$(CC) $(CFLAGS) -o wayland-benchmark wayland-benchmark.c

clean:
	rm -f x11-benchmark wayland-benchmark

.PHONY: all clean
