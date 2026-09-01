#!/usr/bin/env python3
"""Build a deterministic Open-English-Wordnet-style SQLite database.

This mirrors the conventional OEWN relational schema (synsets, words, senses,
and inter-synset relational links) with a fixed random seed so the database is
exactly reproducible on every build. No indexes are created; the task is to
author them.
"""
import sqlite3, sys, random

out = sys.argv[1] if len(sys.argv) > 1 else "/app/wn.db"
N_SYN = int(sys.argv[2]) if len(sys.argv) > 2 else 15000
N_WORDS = int(sys.argv[3]) if len(sys.argv) > 3 else 30000
random.seed(20240424)
POS = ["n", "v", "a"]

con = sqlite3.connect(out)
cur = con.cursor()

cur.executescript(
    """
    DROP TABLE IF EXISTS relations;
    DROP TABLE IF EXISTS senses;
    DROP TABLE IF EXISTS words;
    DROP TABLE IF EXISTS synsets;

    CREATE TABLE synsets (
        id INTEGER PRIMARY KEY,
        pos TEXT NOT NULL,
        definition TEXT NOT NULL
    );
    CREATE TABLE words (
        id INTEGER PRIMARY KEY,
        lemma TEXT NOT NULL
    );
    CREATE TABLE senses (
        id INTEGER PRIMARY KEY,
        synset_id INTEGER NOT NULL,
        word_id INTEGER NOT NULL,
        senserank INTEGER NOT NULL
    );
    CREATE TABLE relations (
        id INTEGER PRIMARY KEY,
        synset_id INTEGER NOT NULL,
        target_synset INTEGER NOT NULL,
        reltype TEXT NOT NULL
    );
    """
)

# --- synsets -------------------------------------------------------------
for i in range(1, N_SYN + 1):
    cur.execute(
        "INSERT INTO synsets (id, pos, definition) VALUES (?,?,?)",
        (i, random.choice(POS), "definition " + str(i)),
    )

# --- words ---------------------------------------------------------------
for i in range(1, N_WORDS + 1):
    cur.execute("INSERT INTO words (id, lemma) VALUES (?,?)", (i, "lemma" + str(i)))

# --- senses : each synset is linked to 1..6 distinct words --------------
# senserank is assigned from a highly skewed distribution so low ranks (1,2)
# are the norm and rank 3 (the value probed by q4/q5) is rare but present.
# This keeps ~400k senses while making the senserank filter genuinely
# selective, so a proper index yields a large, reproducible speedup.
RANK_POOL = [1]*12 + [2]*5 + [3] + [4] + [5] + [6]   # P(3) ~ 1/21
sid = 0
for i in range(1, N_SYN + 1):
    k = random.randint(1, 6)
    word_ids = sorted(random.sample(range(1, N_WORDS + 1), k))
    for wid in word_ids:
        sid += 1
        cur.execute(
            "INSERT INTO senses (id, synset_id, word_id, senserank) VALUES (?,?,?,?)",
            (sid, i, wid, random.choice(RANK_POOL)),
        )

# --- relations : each synset points at 2..7 other synsets ----------------------
rid = 0
for i in range(1, N_SYN + 1):
    for tgt in random.sample(range(1, N_SYN + 1), random.randint(2, 7)):
        rid += 1
        cur.execute(
            "INSERT INTO relations (id, synset_id, target_synset, reltype) VALUES (?,?,?,?)",
            (rid, i, tgt, random.choice(["hypernym", "hyponym", "holonym", "meronym"])),
        )

con.commit()
con.close()
print("built deterministic wordnet db at", out)