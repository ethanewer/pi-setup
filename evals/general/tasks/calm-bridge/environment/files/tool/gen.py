#!/usr/bin/env python3
"""calm-bridge fixture generator.

Builds the damaged-and-transformed SQLite scenario for a given seed, plus the
scaled database used by the performance check. This tool ships as part of the
/app environment so the agent can regenerate inputs while developing the
deliverable (/app/recover.py). recover.py must never depend on this file.

The journal format and cleaning contract described here match
instruction.md exactly and are the source of truth for the hidden cases.
"""
import os
import random
import sqlite3
import json

# ---------------------------------------------------------------------------
# Shared format contract (also documented in instruction.md)
# ---------------------------------------------------------------------------
MAGIC = b"WJNT1\n"                 # heading of the native (untransformed) journal
FIELD_NAMES = ["id", "name", "msisdn", "email", "phone", "region"]

KIWIS = ["taro", "pica", "ocelot", "radius", "quince", "feint", "halcyon",
         "dahlia", "vertex", "cobalt", "umbra", "tundra", "lumen", "mirror",
         "zephyr", "cornice", "violet", "bandit", "flax", "orizon"]
SURNAMES = ["north", "wraiths", "aardvark", "kills", "sundial", "kepler",
            "marsh", "hale", "bracken", "loom", "sable", "trakt", "nyx",
            "yarrow"]
REGIONS = ["sea", "coast", "harbor", "fjord", "atoll", "sound"]
LETTERS = "QWRTYFGHJKLZVCXBNM"


def digits_only(value):
    """Return the ASCII 0-9 substring of *value* ('' when absent)."""
    if value is None:
        return ""
    return "".join(ch for ch in str(value) if "0" <= ch <= "9")


def clean_rows(rows):
    """Apply the documented cleaning pipeline to a list of row dicts.

     1. *name* lowercased (and stripped)
     2. digits-only *msisdn* cast to int into new field *msisdn_d*
     3. drop rows missing BOTH *email* and *phone*
     4. deduplicate by *id*, keeping the first occurrence in input order
     5. sort ascending by *id*
    """
    seen = set()
    out = []
    for r in rows:
        rid = r["id"]
        if rid in seen:
            continue
        seen.add(rid)
        email = (r.get("email") or "").strip()
        phone = (r.get("phone") or "").strip()
        if not email and not phone:
            continue
        name = (r.get("name") or "").strip().lower()
        d = digits_only(r.get("msisdn"))
        out.append({
            "id": rid,
            "name": name,
            "msisdn": r.get("msisdn") or "",
            "msisdn_d": int(d) if d else None,
            "email": email or None,
            "phone": phone or None,
            "region": r.get("region") or "",
        })
    out.sort(key=lambda r: r["id"])
    return out


def make_row(i, rng):
    """Deterministic-ish pseudo row for id *i*; varies via *rng*."""
    name = "{}.{}.{}".format(rng.choice(KIWIS), rng.choice(SURNAMES), i)
    if rng.random() < 0.1:
        msisdn = "".join(rng.choice(LETTERS) for _ in range(rng.randint(2, 4)))
    else:
        msisdn = "".join(rng.choice(LETTERS + "0123456789")
                         for _ in range(rng.randint(4, 9)))
    drop_both = rng.random() < 0.06
    email = "" if (drop_both and rng.random() < 0.5) \
        else "u{}@{}".format(i, rng.choice(["net", "co", "ini", "wire"]))
    phone = "" if drop_both else "555-{:04d}".format(rng.randint(1, 9999))
    region = rng.choice(REGIONS)
    return {"id": i, "name": name, "msisdn": msisdn,
            "email": email, "phone": phone, "region": region}


def encode_native(rows):
    """Serialize rows into the journal every-byte byte layout."""
    out = bytearray(MAGIC)
    for r in rows:
        line = "\t".join(str(r.get(f, "")) for f in FIELD_NAMES)
        out += line.encode("utf-8") + b"\n"
    return bytes(out)


def transform(key, blob):
    """Byte-wise XOR of every byte with single skip key *key*."""
    return bytes(b ^ key for b in blob)


def build_fixture(root, seed, nrows, journal_share=0.35, damage_share=0.12,
                  dup_share=0.12, malformed_lines=0):
    """Create a damaged-and-transformed SQLite scenario under *root*.

    Files produced:
      <root>/ledger.db            live SQLite DB containing checkpointed rows
      <root>/ledger.wal    XOR-transformed journal (extra/duplicate rows)
      <root>/.scenario.json       private truth used by hidden checks
    If *malformed_lines>0*, that many structurally-broken records (wrong field
    count / non-numeric id) are appended to the journal. They are not part of
    the recoverable truth and a correct recoverer must simply skip them.
    Returns the scenario dict.
    """
    rng = random.Random(seed)
    os.makedirs(root, exist_ok=True)
    key = (seed % 255) + 1

    rows_all = [make_row(i, rng) for i in range(1, nrows + 1)]

    db_rows, journal_rows, dropped = [], [], []
    for r in rows_all:
        t = rng.random()
        if t < journal_share:
            journal_rows.append(dict(r))
        elif t < journal_share + damage_share:
            dropped.append(dict(r))                 # damaged/lost: never there
        else:
            db_rows.append(dict(r))

    # Duplicate-id rows placed only in the journal force the dedupe step.
    for _ in range(max(0, int(nrows * dup_share))):
        i = rng.randint(1, nrows)
        if any(x["id"] == i for x in db_rows):
            dupc = dict(make_row(i, rng))
            dupc["name"] = dupc["name"] + ".dup"
            dupc["id"] = i
            journal_rows.append(dupc)
        # note: duplicates that collide with journal already in db are fine too

    dbpath = os.path.join(root, "ledger.db")
    for p in (dbpath, dbpath + "-journal", dbpath + "-wal", dbpath + "-shm"):
        if os.path.exists(p):
            os.remove(p)
    conn = sqlite3.connect(dbpath)
    conn.execute("CREATE TABLE contacts("
                 "id INTEGER PRIMARY KEY, name TEXT, msisdn TEXT, "
                 "email TEXT, phone TEXT, region TEXT)")
    conn.executemany(
        "INSERT INTO contacts(id,name,msisdn,email,phone,region) "
        "VALUES(:id,:name,:msisdn,:email,:phone,:region)",
        db_rows)
    conn.commit()
    conn.close()

    native = encode_native(journal_rows)
    if malformed_lines:
        rng2 = random.Random(key)
        bad = []
        for _j in range(malformed_lines):
            kind = _j % 3
            if kind == 0:
                bad.append("not-a-row (bad field count)")
            elif kind == 1:
                bad.append("7\tfields\there\tare\ttoo\tmany\tfor\teight")
            else:
                bad.append("abc\tname\tmsisdn\te\tp\tr")
            native += bad[-1].encode("utf-8") + b"\n"
    jpath = os.path.join(root, "ledger.wal")
    with open(jpath, "wb") as f:
        f.write(transform(key, native))

    # NOTE: nothing about the truth is persisted next to the input files. The
    # oracle answer is derived only from the *returned* info dict, so a solver
    # operating on the fixture directory cannot read a planted answer file.
    return {
        "root": root, "nrows": nrows, "key": key,
        "db_rows": db_rows, "journal_rows": journal_rows, "dropped": dropped,
    }


def expected(info):
    """Oracle answer (cleaned/ordered/deduped) for a scenario *info* dict."""
    return clean_rows(info["db_rows"] + info["journal_rows"])


def build_scaled(dbpath, nrows, seed=7):
    """Create a large indexed metrics DB for the perf check."""
    rng = random.Random(seed)
    if os.path.exists(dbpath):
        os.remove(dbpath)
    conn = sqlite3.connect(dbpath)
    conn.execute("CREATE TABLE metrics("
                 "id INTEGER PRIMARY KEY, grp INTEGER NOT NULL, "
                 "val REAL, stub TEXT)")   # note: no index -- agent must tune
    n_groups = 64
    rows = []
    for i in range(1, nrows + 1):
        rows.append((i, i % n_groups, rng.random() * 10000.0, "stub%d" % (i % 9)))
    conn.executemany("INSERT INTO metrics VALUES(?,?,?,?)", rows)
    conn.commit()
    conn.close()
    return nrows


def build_seed(path, seed=99):
    """Write the 'service draft' content used by the open-fd recovery demo."""
    rng = random.Random(seed)
    lines = [
        "ledger-journal salvage draft",
        "checksum slot=%d flag=%d" % (rng.randint(0, 10 ** 9), rng.randint(0, 3)),
        "continuation:" + rng.randbytes(240).hex(),
    ]
    content = "\n".join(lines)
    with open(path, "w") as f:
        f.write(content)
    return content


if __name__ == "__main__":
    import sys
    cmd = sys.argv[1]
    if cmd == "fresh":
        root, seed, nrows = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
        info = build_fixture(root, seed, nrows)
        print("built fixture:", root, "key=", info["key"],
              "db=", len(info["db_rows"]), "journal=", len(info["journal_rows"]),
              "dropped=", len(info["dropped"]))
    elif cmd == "scaled":
        path, nrows = sys.argv[2], int(sys.argv[3])
        print("scaled rows:", build_scaled(path, nrows))
    elif cmd == "seed":
        build_seed(sys.argv[2])
        print("seed written:", sys.argv[2])
    else:
        raise SystemExit("usage: gen.py fresh|scaled|seed")