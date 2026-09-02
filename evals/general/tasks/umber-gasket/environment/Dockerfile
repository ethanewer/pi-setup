FROM bench-base:python-3.12

WORKDIR /app

# python-chess provides a real beat-up reference for the knight-move engine and
# is small; the deliverables themselves are all hand-written.
RUN pip install --no-cache-dir -q python-chess

# Read-only fixtures illustrating the scenario inputs (sample starter FEN and a
# tiny M program). The four deliverables are created by the agent under /app.
COPY files/ /app/

# Deliberately leaving: eval.py, moves.fen.rules, gate_net.txt, simulate.py are
# produced by the agent's solve.sc stage and NOT shipped in this image.