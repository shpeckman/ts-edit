# Makefile
CRYSTAL ?= crystal
CC ?= cc
AR ?= ar
CFLAGS ?= -O2 -fPIC -std=gnu11
BIN := bin/ts-edit
DEPS := vendor/deps
BUILD := vendor/build
TS := $(DEPS)/tree-sitter-lib
GRAMMAR_OBJS := $(BUILD)/json.o $(BUILD)/crystal_parser.o $(BUILD)/crystal_scanner.o $(BUILD)/crystal_unicode.o $(BUILD)/python_parser.o $(BUILD)/python_scanner.o $(BUILD)/c_parser.o $(BUILD)/bash_parser.o $(BUILD)/bash_scanner.o
SOURCES := $(wildcard src/*.cr src/ts-edit/*.cr)
PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

.PHONY: all clean install uninstall native spec examples

all: $(BIN)

native: $(BUILD)/libtree-sitter.a $(GRAMMAR_OBJS)

spec: native
	$(CRYSTAL) spec

examples: native
	$(CRYSTAL) run examples/library_usage.cr

$(DEPS): vendor/tree-sitter-deps.tar.gz
	tar xzf $< -C vendor
	touch $@

$(BUILD)/libtree-sitter.a: $(DEPS)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -I$(TS)/include -I$(TS)/src -c $(TS)/src/lib.c -o $(BUILD)/ts_lib.o
	$(AR) rcs $@ $(BUILD)/ts_lib.o

$(BUILD)/json.o: $(DEPS)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -I$(DEPS)/json -c $(DEPS)/json/parser.c -o $@

$(BUILD)/%_parser.o: $(DEPS)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -I$(DEPS)/$* -c $(DEPS)/$*/parser.c -o $@

$(BUILD)/%_scanner.o: $(DEPS)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -I$(DEPS)/$* -c $(DEPS)/$*/scanner.c -o $@

$(BUILD)/crystal_unicode.o: $(DEPS)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -I$(DEPS)/crystal -c $(DEPS)/crystal/unicode.c -o $@

$(BIN): $(BUILD)/libtree-sitter.a $(GRAMMAR_OBJS) $(SOURCES)
	mkdir -p bin
	$(CRYSTAL) build --release --no-debug src/cli.cr -o $(BIN)

install: $(BIN)
	mkdir -p $(BINDIR)
	install -m 755 $(BIN) $(BINDIR)/ts-edit

uninstall:
	rm -f $(BINDIR)/ts-edit

clean:
	rm -rf $(BUILD) $(DEPS) bin
