# Copyright (c) 2025 Michael Matta
# Makefile for zsh-edit-select Wayland selection monitor
#
# Prerequisites:
#   - wayland-client library (libwayland-dev / wayland-devel)
#   - wayland-scanner (wayland-scanner / wayland-scanner)
#
# Build: make
# Clean: make clean

CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-parameter
WAYLAND_SCANNER ?= $(shell pkg-config --variable=wayland_scanner wayland-scanner 2>/dev/null || echo wayland-scanner)
WAYLAND_CFLAGS := $(shell pkg-config --cflags wayland-client 2>/dev/null)
WAYLAND_LIBS := $(shell pkg-config --libs wayland-client 2>/dev/null || echo -lwayland-client)

TARGET = zes-wl-selection-monitor
PROTO_XML = primary-selection-unstable-v1.xml
PROTO_HEADER = primary-selection-unstable-v1-client-protocol.h
PROTO_CODE = primary-selection-unstable-v1-protocol.c

XDG_SHELL_XML = $(shell pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null || echo /usr/share/wayland-protocols)/stable/xdg-shell/xdg-shell.xml
XDG_SHELL_HEADER = xdg-shell-client-protocol.h
XDG_SHELL_CODE = xdg-shell-protocol.c

.PHONY: all clean

all: $(TARGET)

$(PROTO_HEADER): $(PROTO_XML)
	$(WAYLAND_SCANNER) client-header $(PROTO_XML) $(PROTO_HEADER)

$(PROTO_CODE): $(PROTO_XML)
	$(WAYLAND_SCANNER) private-code $(PROTO_XML) $(PROTO_CODE)

$(XDG_SHELL_HEADER): $(XDG_SHELL_XML)
	$(WAYLAND_SCANNER) client-header $(XDG_SHELL_XML) $(XDG_SHELL_HEADER)

$(XDG_SHELL_CODE): $(XDG_SHELL_XML)
	$(WAYLAND_SCANNER) private-code $(XDG_SHELL_XML) $(XDG_SHELL_CODE)

$(TARGET): zes-wl-selection-monitor.c $(PROTO_HEADER) $(PROTO_CODE) $(XDG_SHELL_HEADER) $(XDG_SHELL_CODE)
	$(CC) $(CFLAGS) $(WAYLAND_CFLAGS) -o $(TARGET) zes-wl-selection-monitor.c $(PROTO_CODE) $(XDG_SHELL_CODE) $(WAYLAND_LIBS)

clean:
	rm -f $(TARGET) $(PROTO_HEADER) $(PROTO_CODE) $(XDG_SHELL_HEADER) $(XDG_SHELL_CODE)
