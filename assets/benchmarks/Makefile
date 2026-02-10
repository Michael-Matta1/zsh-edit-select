# Makefile for benchmark tools

CC ?= gcc
COMMON_FLAGS = -march=native -mtune=native -flto \
               -ffunction-sections -fdata-sections \
               -fomit-frame-pointer \
               -fno-plt -pipe -fno-semantic-interposition \
               -Wall -Wextra -std=c99
CFLAGS ?= -O3 $(COMMON_FLAGS)
LDFLAGS = -Wl,--gc-sections -Wl,--as-needed -flto -s

all: x11-benchmark wayland-benchmark

x11-benchmark: x11-benchmark.c
	$(CC) $(CFLAGS) -o x11-benchmark x11-benchmark.c $(LDFLAGS)

wayland-benchmark: wayland-benchmark.c
	$(CC) $(CFLAGS) -o wayland-benchmark wayland-benchmark.c $(LDFLAGS)

test-o2:
	$(MAKE) clean
	$(MAKE) CFLAGS="-O2 $(COMMON_FLAGS)" LDFLAGS="$(LDFLAGS)"

test-o3:
	$(MAKE) clean
	$(MAKE) CFLAGS="-O3 $(COMMON_FLAGS)" LDFLAGS="$(LDFLAGS)"

clean:
	rm -f x11-benchmark wayland-benchmark

.PHONY: all clean test-o2 test-o3
