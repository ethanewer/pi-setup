FROM bench-base:python-3.12

WORKDIR /app

# A Debian-style package source descriptor list. Records separated by blank lines,
# each field a "Key: value" line.
RUN cat > /app/debian-sources.list <<'EOF2'
Name: zlib
Version: 1.2.13
Priority: 3

Name: gtk
Version: 4.10.5
Priority: 2

Name: ffmpeg
Version: 6.1.1
Priority: 1

Name: libpng
Version: 1.6.43
Priority: 4
EOF2
