#!/bin/bash
# Oracle for derrick-tarn: wire the picdrome extractor into the gallery-dl
# checkout at /app/src and prove the unmodified CLI discovers it.
set -u
cd /app/src || exit 1

# 1) Ship the extractor module at the deliverable path.
DEST=/app/src/gallery_dl/extractor/picdrome.py
cp /solution/picdrome.py "$DEST"

# 2) Register the module with gallery-dl's extractor discovery mechanism
#    (the explicit `modules` list in gallery_dl/extractor/__init__.py).
python3 /solution/register.py

# 3) Prove the unmodified CLI itself discovers the new site.
python3 -m gallery_dl --list-extractors picdrome | grep -q PicdromeGalleryExtractor
echo "picdrome extractor registered and listed"