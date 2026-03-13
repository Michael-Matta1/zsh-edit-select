# Makefile for XWayland agent (WSL Tailored Variant)
CC ?= gcc
CFLAGS ?= -O3 -Wall -Wextra
LIBS = -lX11 -lXfixes

all: zes-xwayland-agent

zes-xwayland-agent: zes-xwayland-agent.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)

clean:
	rm -f zes-xwayland-agent

.PHONY: all clean
