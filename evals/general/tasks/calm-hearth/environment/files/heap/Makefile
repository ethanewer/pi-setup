# calm-hearth heap build (PROTECTED -- do not rename targets, flags or files).
CXX      := g++
CXXFLAGS := -O2 -Wall -Wextra -Wno-unused-parameter -std=c++17
OBJS     := user.o main.o

.PHONY: all clean

all: fixedheap

fixedheap: $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS)

user.o: user.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f fixedheap $(OBJS)