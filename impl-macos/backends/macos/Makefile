# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Makefile for the zsh-edit-select macOS pasteboard agent.
#
# Prerequisites:
#   Apple Command Line Tools: xcode-select --install
#   (provides clang, AppKit/Foundation/ApplicationServices/CoreGraphics headers)
#
# Build: make
# Clean: make clean
#
# IMPORTANT — macOS linker (ld64) flags differ from Linux (ELF/GNU ld):
#   Use -Wl,-dead_strip instead of -Wl,--gc-sections
#   Do NOT use -Wl,--as-needed, -Wl,-z,now, -Wl,-z,relro (ELF-only)
#   Do NOT use -s via linker; use 'strip' command after build
#   Do NOT use -fno-plt, -fno-semantic-interposition, -fipa-pta (unsupported by Apple clang)
#   Do NOT use -fno-asynchronous-unwind-tables / -fno-unwind-tables (breaks ObjC exceptions)

CC      ?= clang

# Compiler flags:
#   -Os                  Optimize for size.
#   -fobjc-arc           Automatic Reference Counting.
#   -ffunction-sections  Enables -dead_strip to eliminate unreachable functions.
#   -fdata-sections      Enables -dead_strip to eliminate unreachable data.
#   -fomit-frame-pointer Saves one register in the hot path.
#   -fno-ident           Suppresses compiler ident string in object file.
#   -DNDEBUG             Disables assert() calls.
CFLAGS  ?= -Os \
            -fobjc-arc \
            -ffunction-sections \
            -fdata-sections \
            -fomit-frame-pointer \
            -fno-ident \
            -DNDEBUG \
            -Wall -Wextra -Wno-unused-parameter

# Linker flags:
#   -framework AppKit              NSPasteboard, GCD (libdispatch), Foundation.
#   -framework ApplicationServices AXUIElement, CGEventTap (via HIServices/CG).
#   -framework CoreGraphics        CGEventTapCreate, CGEventMask, mouse events.
#   -lm                            sqrt() for drag-distance calculation.
#   -Wl,-dead_strip                Remove unreachable code/data.
LDFLAGS = -framework AppKit \
           -framework ApplicationServices \
           -framework CoreGraphics \
           -lm \
           -Wl,-dead_strip

TARGET  = zes-macos-clipboard-agent
SRC     = zes-macos-clipboard-agent.m

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	strip $@ 2>/dev/null || true

clean:
	rm -f $(TARGET)
