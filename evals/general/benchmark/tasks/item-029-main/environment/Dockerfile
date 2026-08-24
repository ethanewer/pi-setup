FROM bench-base:python-3.12

WORKDIR /app

# Generate a large, noisy G-code toolpath (an isle-nameplate print job).
# The genuine printed segments carry a part-extrusion token `E` whose integer
# part silently encodes one letter each; the rest is travel / temperature /
# drafting metadata.
COPY files/build_gcode.py /app/build_gcode.py
RUN python3 /app/build_gcode.py && rm /app/build_gcode.py