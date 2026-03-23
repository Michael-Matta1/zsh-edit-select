# Makefile for XWayland agent (WSL Tailored Variant)
CC ?= gcc
CFLAGS ?= -O3 -flto \
          -ffunction-sections -fdata-sections \
          -fomit-frame-pointer -funroll-loops \
          -fno-plt -pipe -fno-semantic-interposition \
          -fno-strict-aliasing \
          -fno-asynchronous-unwind-tables -fno-unwind-tables \
          -fmerge-all-constants -fipa-pta -fno-ident \
          -fno-stack-protector \
          -DNDEBUG \
          -Wall -Wextra -Wno-unused-parameter
LDFLAGS = -lX11 -lXfixes -Wl,--gc-sections -Wl,--as-needed \
          -Wl,-z,now -Wl,-z,relro -Wl,-z,noexecstack \
          -Wl,-O1 -Wl,--hash-style=gnu -Wl,--build-id=none \
          -flto -s

all: zes-xwayland-agent

zes-xwayland-agent: zes-xwayland-agent.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

clean:
	rm -f zes-xwayland-agent

.PHONY: all clean
