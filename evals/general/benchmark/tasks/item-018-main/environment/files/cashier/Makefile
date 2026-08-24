# Makefile for the ledger simulator. IMMUTABLE (see README.md).
CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -I.
LDFLAGS  :=

BUILD    := build

DEBUG_FLAGS   := -O0 -g -DDEBUG_CHECKPOOL
RELEASE_FLAGS := -O2 -DNDEBUG

all: debug release

debug: $(BUILD)/debug/cashier
release: $(BUILD)/release/cashier

$(BUILD)/debug/cashier: main.cpp pool.cpp pool.h
	@mkdir -p $(BUILD)/debug
	$(CXX) $(CXXFLAGS) $(DEBUG_FLAGS) -o $@ main.cpp pool.cpp $(LDFLAGS)

$(BUILD)/release/cashier: main.cpp pool.cpp pool.h
	@mkdir -p $(BUILD)/release
	$(CXX) $(CXXFLAGS) $(RELEASE_FLAGS) -o $@ main.cpp pool.cpp $(LDFLAGS)

clean:
	rm -rf $(BUILD)

.PHONY: all debug release clean
