# Copyright (c) 2025 Michael Matta
# Version: 0.6.4
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Makefile for zsh-edit-select macOS pasteboard agent.
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
#   -Os                  Optimize for size: keeps binary small in I-cache.
#   -fobjc-arc           Automatic Reference Counting — no manual retain/release needed.
#   -ffunction-sections  Enables -dead_strip to eliminate unreachable functions.
#   -fdata-sections      Enables -dead_strip to eliminate unreachable data.
#   -fomit-frame-pointer Saves one register in the hot path (event callback and AX read).
#   -fno-ident           Suppresses compiler ident string in object file.
#   -DNDEBUG             Disables assert() calls.
#   NOTE: No -Wno-deprecated-declarations needed because daemon(3) is NOT used.
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
#   -framework ApplicationServices AXUIElement, AXObserver, CGEventTap (via HIServices
#                                  and CoreGraphics, both bundled in ApplicationServices).
#   -framework CoreGraphics        CGEventTapCreate, CGEventMask, kCGEventLeftMouseUp.
#                                  Explicitly linked for clarity even though
#                                  ApplicationServices.framework bundles it.
#   -Wl,-dead_strip                macOS ld64 equivalent of GNU ld's --gc-sections.
#                                  Removes unreachable code/data after -ffunction-sections.
LDFLAGS = -framework AppKit \
           -framework ApplicationServices \
           -framework CoreGraphics \
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
