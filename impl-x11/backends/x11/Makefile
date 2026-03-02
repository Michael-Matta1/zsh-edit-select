# Copyright (c) 2025 Michael Matta
# Makefile for zsh-edit-select X11 selection agent
#
# Prerequisites:
#   - libX11 (libx11-dev / libX11-devel)
#   - libXfixes (libxfixes-dev / libXfixes-devel)
#
# Build: make
# Clean: make clean

CC ?= gcc
CFLAGS ?= -O3 -march=native -mtune=native -flto \
          -ffunction-sections -fdata-sections \
          -fomit-frame-pointer -funroll-loops \
          -fno-plt -pipe -fno-semantic-interposition \
          -fno-strict-aliasing \
          -fno-asynchronous-unwind-tables \
          -fmerge-all-constants -fipa-pta -DNDEBUG \
          -Wall -Wextra -Wno-unused-parameter
LDFLAGS = -lX11 -lXfixes -Wl,--gc-sections -Wl,--as-needed \
          -Wl,-z,now -Wl,-z,relro -flto -s

TARGET = zes-x11-selection-agent
SRC = zes-x11-selection-agent.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)
