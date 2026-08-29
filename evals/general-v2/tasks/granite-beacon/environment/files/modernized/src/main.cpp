// choron - "granary" converter. Legacy code authored against a 2003-era
// toolchain on a shared Unix box. It relies on a handful of constructs that
// this container's modern C++17 compiler rejects; modernize it.
#include <iostream>
#include <memory>
#include <string>
#include <hash>                 // legacy non-standard header (no longer shipped)
#include "digit.h"

static void process_line(const std::string &raw) {
    std::string::size_type eq = raw.find('=');
    if (eq == std::string::npos) return;

    std::string key = trim(raw.substr(0, eq));
    std::string value = raw.substr(eq + 1);

    int s = digit_sum(value);
    if (s < 0) return;          // no digits in the value => skip

    register int i = 0;                      // removed in C++17
    (void)i;

    std::auto_ptr<std::string> tag(new std::string(key)); // removed in C++17
    register int j = static_cast<int>(tag->size());       // removed in C++17
    (void)j;

    std::cout << key << ":" << s << "\n";
}

int main() {
    std::string line;
    while (std::getline(std::cin, line)) process_line(line);
    return 0;
}