#!/bin/bash
set -euo pipefail

cat > /app/analyze.sh <<'SH'
#!/bin/bash
set -euo pipefail

elf=$(objdump -f /app/prog | sed -n 's/.*file format //p')
entry=$(readelf -h /app/prog | sed -n 's/.*Entry point address:[[:space:]]*//p' | tr 'A-F' 'a-f')
secret=$(strings /app/prog | grep -o 'harbor-binary-secret-[0-9]*' | head -1)

printf 'elf=%s\nentry=%s\nsecret=%s\n' "$elf" "$entry" "$secret" > /app/analysis.txt
SH
chmod +x /app/analyze.sh
/app/analyze.sh