CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror
INCLUDES = -I../../include
SOURCES = asset_server.c ../../src/asset_protocol.c ../../src/net_asset_server.c
ifeq ($(OS),Windows_NT)
LDLIBS = -lws2_32
TARGET = asset_server.exe
else
TARGET = asset_server
endif

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ $(SOURCES) $(LDLIBS)

.PHONY: all
