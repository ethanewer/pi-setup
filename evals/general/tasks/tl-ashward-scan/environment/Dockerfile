# tl-ashward-scan — Ashward Workbench rootfs with planted persistence artifacts.
#
# The image ships the visible fixture tree at /app/rootfs (nothing else the
# agent needs: stdlib python3 covers the whole task). The verifier's
# reference scanner lives under /tests only and is never part of the image.

FROM bench-base:python-3.12

WORKDIR /app

# Visible fixture: fabricated rootfs tree with planted persistence artifacts
# and benign lookalikes across the documented locations.
COPY files/ /app/

# No network access at agent or verifier runtime; everything is on-disk.