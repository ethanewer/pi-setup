#!/usr/bin/env python3
"""Write a log file containing ANSI terminal escape sequences."""
lines = [
    "\x1b[32mINFO:\x1b[0m started flow",
    "\x1b[33mWARN:\x1b[0m retrying request",
    "\x1b[31mERROR:\x1b[0m backend timeout",
]
with open("/app/log.txt", "w") as fh:
    fh.write("\n".join(lines) + "\n")
print("log written")