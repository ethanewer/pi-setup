FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir python-chess==1.999

COPY files/board.png /app/board.png

# A claimed move that the agent must cross-check (it is NOT a mating move).
RUN printf 'a1b1\n' > /app/claim.txt