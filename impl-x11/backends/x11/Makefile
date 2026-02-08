# Copyright (c) 2025 Michael Matta
# Makefile for zsh-edit-select X11 selection monitor
#
# Prerequisites:
#   - libX11 (libx11-dev / libX11-devel)
#   - libXfixes (libxfixes-dev / libXfixes-devel)
#
# Build: make
# Clean: make clean

CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
LDFLAGS = -lX11 -lXfixes

TARGET = zes-x11-selection-monitor
SRC = zes-x11-selection-monitor.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)
