#!/usr/bin/env python3
"""Build clean-room fixtures for the juniper-quill task.

Produces:
  - environment/files/warehouse/inventory.db     (damaged: 4-byte-XOR + survivors only)
  - environment/files/warehouse/inventory.db-wal (crafted WAL header, same XOR)
  - environment/files/archive/lost.csv           (unlinked-at-runtime fd source)
  - tests/fd_expected.txt                        (golden copy of lost.csv)
  - tests/hidden/<case>/warehouse/inventory.db (+ -wal) for H1..H3
Everything is invented for this task (no Terminal-Bench content).
"""
import os, random, sqlite3, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = os.path.join(ROOT, "environment", "files")
TESTS = os.path.join(ROOT, "tests")

WAL_MAGIC = bytes([0x37, 0x7f, 0x06, 0x82])


def xor_transform(data: bytes, key) -> bytes:
    """Repeating 4-byte XOR."""
    return bytes(b ^ key[i % 4] for i, b in enumerate(data))


def craft_wal_header(key) -> bytes:
    """A 32-byte SQLite-style WAL header (magic + zeros) transformed by key."""
    hdr = WAL_MAGIC + bytes(4) + bytes(24)  # 32 bytes
    return xor_transform(hdr, key)


NAMES = [
    "Adaeze Obi", "Bram Kessler", "Calla Reyes", "Demba Sow", "Elif Yildiz",
    "Farid Haddad", "Greta Lindqvist", "Hiroshi Tanabe", "Imani Bello",
    "Jules Moreau", "Kareem Haddad", "Leah Novak", "Matteo Ricci", "Nadia Zouari",
    "Olga Petrov", "Priya Raman", "Quinn Brody", "Rafael Duarte", "Sigrid Halvorsen",
    "Tomasz Kowalski", "Uma Patel", "Viktor Lindholm", "Willem de Vries",
    "Ximena Flores", "Yusuf Karim", "Zainab Hassan", "Aiko Nakamura",
    "Binta Diallo", "Carlo Bianchi", "Dalia Abadi", "Elias Costa", "Fatima Ziani",
    "Gideon Achebe", "Hana Sasaki", "Idris Okafor", "Jana Kovar", "Kenji Mori",
    "Lara Haddad", "Mei Chen", "Nils Berg", "Omar Farouk", "Pilar Ortiz",
    "Rashid Khan", "Sofia Lindgren", "Teo Vasquez", "Unika Sharma", "Vera Novak",
    "Wei Zhang", "Yara Saleh", "Zara Iqbal",
]


def make_person(rng, i, idv):
    name = rng.choice(NAMES)
    if rng.random() < 0.4:
        name = name.upper()
    elif rng.random() < 0.4:
        name = name.title()
    has_email = rng.random() < 0.55
    has_phone = rng.random() < 0.55
    email = ("p%04d@brightshard.test" % idv) if has_email else ""
    phone = ("+1-555-01%02d-%04d" % (rng.randrange(100), rng.randrange(10000))) if has_phone else ""
    if rng.random() < 0.08:
        email = ""
        has_email = False
    if rng.random() < 0.08:
        phone = ""
        has_phone = False
    value = rng.randrange(0, 5_000_000)
    if rng.random() < 0.2:
        value_txt = "%07d" % value
    else:
        value_txt = str(value)
    balance = rng.randrange(0, 1_000_000)
    return (idv, name, email, phone, value_txt, balance)


def build_case(outdir, key, seed, n_intended, n_lost, n_dup, n_no_contact):
    rng = random.Random(seed)
    os.makedirs(outdir, exist_ok=True)
    dbpath = os.path.join(outdir, "inventory.db")
    walpath = dbpath + "-wal"
    if os.path.exists(dbpath):
        os.remove(dbpath)
    if os.path.exists(walpath):
        os.remove(walpath)
    con = sqlite3.connect(dbpath)
    con.execute("CREATE TABLE customers(id INTEGER, name TEXT, email TEXT,"
                " phone TEXT, value TEXT, balance INTEGER)")
    lost_ids = set(rng.sample(range(1, n_intended + 1), n_lost)) if n_lost else set()
    rows = []
    for i in range(1, n_intended + 1):
        if i in lost_ids:
            continue
        rows.append(make_person(rng, i, i))
    # rows missing both contact fields (cleaning must delete them)
    for _ in range(n_no_contact):
        rows.append((rng.randrange(1, n_intended + 1), "Ghost Contact",
                     "", "", "0", 0))
    # explicit duplicate rows of a few ids (cleaning must dedup)
    dup_targets = rng.sample(range(1, n_intended + 1), n_dup) if n_dup else []
    for t in dup_targets:
        rows.append(make_person(rng, t + 100000, t))
    # ensure at least a couple of rows with email only and phone only
    for _ in range(6):
        rows.append((rng.randrange(1, n_intended + 1), "Partial Contact",
                     "n%d@brightshard.test" % rng.randrange(100000), "", "1", 1))
    rng.shuffle(rows)
    con.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?)", rows)
    con.commit()

    # operational audit table (only for the visible case; hidden cases skip it)
    if n_intended >= 100:
        con.execute("CREATE TABLE audit(id INTEGER, balance INTEGER)")
        n_audit = 600000
        con.executemany("INSERT INTO audit VALUES (?,?)",
                        ((i, (i * 2654435761) % 1000000) for i in range(n_audit)))
        con.commit()
    con.close()

    # apply transform
    with open(dbpath, "rb") as f:
        raw = f.read()
    with open(dbpath, "wb") as f:
        f.write(xor_transform(raw, key))
    with open(walpath, "wb") as f:
        f.write(craft_wal_header(key))


def build_lost_csv(dirpath, text):
    os.makedirs(dirpath, exist_ok=True)
    with open(os.path.join(dirpath, "lost.csv"), "w") as f:
        f.write(text)


LOST_CSV = """location,sensor,reading,unit,timestamp
north-rack,aht,23.8,c,2026-01-14T09:12:03Z
north-rack,hum,41.2,pct,2026-01-14T09:12:03Z
south-rack,aht,24.9,c,2026-01-14T09:12:04Z
south-rack,hum,38.7,pct,2026-01-14T09:12:04Z
east-cab,psu,12.4,v,2026-01-14T09:12:05Z
west-cab,psu,12.2,v,2026-01-14T09:12:05Z
core-a,fan,5400,rpm,2026-01-14T09:12:06Z
core-b,fan,5300,rpm,2026-01-14T09:12:06Z
storage-1,nvme,44.0,c,2026-01-14T09:13:01Z
storage-2,nvme,43.2,c,2026-01-14T09:13:01Z
storage-1,nvme-health,99.6,pct,2026-01-14T09:13:02Z
storage-2,nvme-health,99.1,pct,2026-01-14T09:13:02Z
edge-1,link,920,mbit,2026-01-14T09:13:03Z
edge-2,link,880,mbit,2026-01-14T09:13:03Z
edge-1,latency,1.2,ms,2026-01-14T09:13:04Z
edge-2,latency,1.4,ms,2026-01-14T09:13:04Z
"""


def main():
    build_lost_csv(os.path.join(ENV, "archive"), LOST_CSV)
    with open(os.path.join(TESTS, "fd_expected.txt"), "w") as f:
        f.write(LOST_CSV)

    # visible case
    build_case(os.path.join(ENV, "warehouse"),
               [0x3c, 0xa7, 0x1d, 0xf0], seed=20260114,
               n_intended=1800, n_lost=240, n_dup=60, n_no_contact=70)

    # hidden cases
    build_case(os.path.join(TESTS, "hidden", "H1", "warehouse"),
               [0x5e, 0x2b, 0x91, 0x0c], seed=777001,
               n_intended=1200, n_lost=300, n_dup=0, n_no_contact=40)
    build_case(os.path.join(TESTS, "hidden", "H2", "warehouse"),
               [0x00, 0x00, 0x00, 0x00], seed=777002,
               n_intended=35, n_lost=4, n_dup=8, n_no_contact=5)
    build_case(os.path.join(TESTS, "hidden", "H3", "warehouse"),
               [0x77, 0x77, 0x77, 0x77], seed=777003,
               n_intended=2600, n_lost=260, n_dup=120, n_no_contact=90)

    print("fixtures written")
    for base in (os.path.join(ENV, "warehouse"), os.path.join(TESTS, "hidden")):
        for root, _, files in os.walk(base):
            for f in files:
                p = os.path.join(root, f)
                print(" ", os.path.relpath(p, ROOT), os.path.getsize(p))


if __name__ == "__main__":
    main()
