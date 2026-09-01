#!/bin/bash
# Oracle for indigo-vault: author /app/crack.sh (the real deliverable), then
# run it on the visible fixtures to produce /app/answer.json and the decrypted
# member. Never reads /tests.
set -eu

CRACK="/app/crack.sh"

# ---- 1. Write the deliverable (this IS the work).
cat > "$CRACK" <<'SH'
#!/bin/bash
# CPU password-cracker + archive unsealer.
# usage: crack.sh <hash_file> <wordlist> <zip_file> <out_dir>
set -eu
HASH_FILE="$1"; WORDLIST="$2"; ZIP_FILE="$3"; OUT_DIR="$4"
mkdir -p "$OUT_DIR"
python3 - "$HASH_FILE" "$WORDLIST" "$ZIP_FILE" "$OUT_DIR" <<'PY'
import hashlib, json, sys, zipfile

hash_path, wordlist_path, zip_path, out_dir = sys.argv[1:5]

with open(hash_path, "r", encoding="utf-8", errors="replace") as fh:
    target = ""
    for line in fh:
        line = line.strip()
        if line:
            target = line.lower()
            break
if not target:
    sys.exit("crack.sh: empty hash file")

password = None
with open(wordlist_path, "r", encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        cand = raw.strip()
        if not cand:
            continue
        if hashlib.sha256(cand.encode("utf-8")).hexdigest() == target:
            password = cand
            break
if password is None:
    sys.exit("crack.sh: digest not cracked from wordlist")

zf = zipfile.ZipFile(zip_path)
infos = [i for i in zf.infolist() if not i.is_dir()]
if len(infos) != 1:
    sys.exit("crack.sh: expected exactly one archive member")
info = infos[0]
data = zf.read(info.filename, pwd=password.encode("utf-8"))
text = data.decode("utf-8")

code = None
for line in text.splitlines():
    line = line.strip()
    if line.startswith("code="):
        code = line[len("code="):].strip()
        break
if not code:
    sys.exit("crack.sh: member has no code= line")

member_path = out_dir.rstrip("/") + "/" + info.filename
with open(member_path, "wb") as fh:
    fh.write(data)

answer = {
    "password": password,
    "hash": target,
    "member": info.filename,
    "code": code,
}
with open(out_dir.rstrip("/") + "/answer.json", "w", encoding="utf-8") as fh:
    json.dump(answer, fh, indent=2)
print("cracked; member=%s code=%s" % (info.filename, code))
PY
SH
chmod +x "$CRACK"

# ---- 2. Run the deliverable on the visible fixtures.
bash "$CRACK" /app/passwd.hash /app/wordlist.txt /app/locker.zip /app

echo "solve.sh done -> $CRACK and /app/answer.json"
ls -l "$CRACK" /app/answer.json /app/release_notes.txt
