CC = gcc
CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter
LDFLAGS = -lX11 -lXfixes

TARGET = zes-xwayland-monitor
SRC = zes-xwayland-monitor.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
