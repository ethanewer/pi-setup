# Crack a password hash

`/app/hash.txt` contains a single line: the hexadecimal **MD5 digest** of a plaintext
password.

`/app/wordlist.txt` is a wordlist: one candidate password per line (all lowercase
ASCII words).

The plaintext password is **one of the words in the wordlist**. Your task is to crack
the hash — i.e. determine which word hashes to the given MD5 digest — and write that
word (lowercase, no trailing whitespace) to `/app/password.txt`.

You may write your own short Python script using the standard library `hashlib` module,
or use any cracking tool available in the environment. The correct password is unique
within the file.

When done, confirm `/app/password.txt` exists and contains only the recovered password
(lowercase, ending with a newline).