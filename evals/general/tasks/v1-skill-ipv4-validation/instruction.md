# IPv4 validation

`/app/ip_candidates.txt` contains a list of candidate strings, one per line. Some are valid IPv4 addresses, some are not.

A string is a **valid IPv4 address** iff:
- It has exactly **4 octets** separated by single dots.
- Each octet consists only of decimal digits.
- Each octet is an integer in the inclusive range **0..255**.
- Decimal representation has no leading zeros unless the octet is exactly `0`.

Examples:
- `192.168.1.1` → valid
- `256.1.1.1` → invalid (256 > 255)
- `1.2.3` → invalid (3 octets)
- `10.0.2.5` → valid

Write to `/app/valid_ip.txt` only the candidate lines that are **valid**, in the same order they appear in the input file, each followed by a newline. Invalid candidates are omitted entirely.

You may implement the check in Python, e.g. using the `ipaddress` module, or by hand:

```python
import ipaddress, sys
out = []
for line in open('/app/ip_candidates.txt'):
    s = line.strip()
    try:
        ip = ipaddress.IPv4Address(s)
        if s == str(ip):   # rejects leading zeros / alternate forms
            out.append(s)
    except:
        pass
open('/app/valid_ip.txt', 'w').write('\n'.join(out) + ('\n' if out else ''))
```

Only IPv4 (not IPv6) candidates count.