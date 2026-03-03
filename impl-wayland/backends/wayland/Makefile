# Copyright (c) 2025 Michael Matta
# Makefile for zsh-edit-select Wayland selection agent
#
# Prerequisites:
#   - wayland-client library (libwayland-dev / wayland-devel)
#   - wayland-scanner (wayland-scanner / wayland-scanner)
#
# Build: make
# Clean: make clean

CC ?= gcc
CFLAGS ?= -O3 -march=native -mtune=native -flto \
          -ffunction-sections -fdata-sections \
          -fomit-frame-pointer -funroll-loops \
          -fno-plt -pipe -fno-semantic-interposition \
          -fno-asynchronous-unwind-tables -fno-unwind-tables \
          -fmerge-all-constants -fipa-pta -fno-ident \
          -fno-stack-protector \
          -DNDEBUG \
          -Wall -Wextra -Wno-unused-parameter
WAYLAND_SCANNER ?= $(shell pkg-config --variable=wayland_scanner wayland-scanner 2>/dev/null || echo wayland-scanner)
WAYLAND_CFLAGS := $(shell pkg-config --cflags wayland-client 2>/dev/null)
WAYLAND_LIBS := $(shell pkg-config --libs wayland-client 2>/dev/null || echo -lwayland-client)
LDFLAGS = $(WAYLAND_LIBS) -Wl,--gc-sections -Wl,--as-needed \
          -Wl,-z,now -Wl,-z,relro -Wl,-z,noexecstack \
          -Wl,-O1 -Wl,--hash-style=gnu -Wl,--build-id=none \
          -flto -s

TARGET = zes-wl-selection-agent
PROTO_XML = primary-selection-unstable-v1.xml
PROTO_HEADER = primary-selection-unstable-v1-client-protocol.h
PROTO_CODE = primary-selection-unstable-v1-protocol.c

XDG_SHELL_XML = $(shell pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null || echo /usr/share/wayland-protocols)/stable/xdg-shell/xdg-shell.xml
XDG_SHELL_HEADER = xdg-shell-client-protocol.h
XDG_SHELL_CODE = xdg-shell-protocol.c

WLR_DC_XML = wlr-data-control-unstable-v1.xml
WLR_DC_HEADER = wlr-data-control-unstable-v1-client-protocol.h
WLR_DC_CODE = wlr-data-control-unstable-v1-protocol.c

EXT_DC_XML = ext-data-control-v1.xml
EXT_DC_HEADER = ext-data-control-v1-client-protocol.h
EXT_DC_CODE = ext-data-control-v1-protocol.c

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

$(WLR_DC_HEADER): $(WLR_DC_XML)
	$(WAYLAND_SCANNER) client-header $(WLR_DC_XML) $(WLR_DC_HEADER)

$(WLR_DC_CODE): $(WLR_DC_XML)
	$(WAYLAND_SCANNER) private-code $(WLR_DC_XML) $(WLR_DC_CODE)

$(EXT_DC_HEADER): $(EXT_DC_XML)
	$(WAYLAND_SCANNER) client-header $(EXT_DC_XML) $(EXT_DC_HEADER)

$(EXT_DC_CODE): $(EXT_DC_XML)
	$(WAYLAND_SCANNER) private-code $(EXT_DC_XML) $(EXT_DC_CODE)

$(TARGET): zes-wl-selection-agent.c $(PROTO_HEADER) $(PROTO_CODE) $(XDG_SHELL_HEADER) $(XDG_SHELL_CODE) $(WLR_DC_HEADER) $(WLR_DC_CODE) $(EXT_DC_HEADER) $(EXT_DC_CODE)
	$(CC) $(CFLAGS) $(WAYLAND_CFLAGS) -o $(TARGET) zes-wl-selection-agent.c $(PROTO_CODE) $(XDG_SHELL_CODE) $(WLR_DC_CODE) $(EXT_DC_CODE) $(LDFLAGS)

clean:
	rm -f $(TARGET) $(PROTO_HEADER) $(PROTO_CODE) $(XDG_SHELL_HEADER) $(XDG_SHELL_CODE) $(WLR_DC_HEADER) $(WLR_DC_CODE) $(EXT_DC_HEADER) $(EXT_DC_CODE)
