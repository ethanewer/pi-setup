#!/usr/bin/env python3
# example ETL probe -- DO NOT MODIFY
def probe(data: bytes) -> int:
    return sum(b for b in data) & 0xFF
if __name__ == '__main__':
    print(f'probe-0-{probe(b"xy")}') 
