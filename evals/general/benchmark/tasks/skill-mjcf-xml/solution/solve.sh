#!/bin/bash
set -euo pipefail

# Fix the MJCF: change the joint type hinge -> slide.
cat > /app/fix_mjcf.py <<'EOF'
import xml.etree.ElementTree as ET

path = '/app/model/pendulum.xml'
tree = ET.parse(path)
root = tree.getroot()

for j in root.iter('joint'):
    if j.get('name') == 'j0':
        j.set('type', 'slide')

tree.write(path, encoding='utf-8', xml_declaration=True)

# Re-parse to confirm well-formedness
ET.parse(path)
EOF

python3 /app/fix_mjcf.py
echo "joint type slide" > /app/report.txt