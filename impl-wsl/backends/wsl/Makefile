# Copyright (c) 2025 Michael Matta
# Makefile for zsh-edit-select WSL clipboard agents
#
# Prerequisites:
#   - gcc (Linux agent)
#   - x86_64-w64-mingw32-gcc (Windows helper — package: gcc-mingw-w64-x86-64)
#
# Build: make
# Clean: make clean

# Linux agent (ELF)
CC ?= gcc
CFLAGS ?= -O3 -march=native -mtune=native -flto \
          -ffunction-sections -fdata-sections \
          -fomit-frame-pointer -funroll-loops \
          -fno-plt -pipe -fno-semantic-interposition \
          -fno-strict-aliasing \
          -fno-asynchronous-unwind-tables -fno-unwind-tables \
          -fmerge-all-constants -fipa-pta -fno-ident \
          -fno-stack-protector \
          -DNDEBUG \
          -Wall -Wextra -Wno-unused-parameter
LDFLAGS = -Wl,--gc-sections -Wl,--as-needed \
          -Wl,-z,now -Wl,-z,relro -Wl,-z,noexecstack \
          -Wl,-O1 -Wl,--hash-style=gnu -Wl,--build-id=none \
          -flto -s

# Windows helper (.exe via MinGW cross-compiler)
MINGW_CC ?= x86_64-w64-mingw32-gcc
MINGW_CFLAGS ?= -O2 -DNDEBUG -Wall -Wextra -Wno-unused-parameter
MINGW_LDFLAGS = -luser32 -s

AGENT = zes-wsl-selection-agent
HELPER = zes-wsl-clipboard-helper.exe
AGENT_SRC = zes-wsl-selection-agent.c
HELPER_SRC = zes-wsl-clipboard-helper.c

.PHONY: all clean

all: $(AGENT) $(HELPER)

$(AGENT): $(AGENT_SRC)
	rm -f $@
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

$(HELPER): $(HELPER_SRC)
	rm -f $@
	$(MINGW_CC) $(MINGW_CFLAGS) -o $@ $< $(MINGW_LDFLAGS)

clean:
	rm -f $(AGENT) $(HELPER)
