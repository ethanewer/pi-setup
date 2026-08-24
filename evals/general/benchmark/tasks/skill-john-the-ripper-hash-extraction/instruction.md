# John the Ripper: hash extraction

`/app/secrets.htpasswd` is a line from an Apache-style `.htpasswd` password file:

```
admin:<HASH-TOKEN>
```

Your job has two parts:

1. **Extract** the raw hash token — the part after the colon — from the file and write it verbatim to `/app/extracted_hash.txt` (token only, ending with newline, no username/colon).
2. **Identify** the hash format family so you could feed it to **John the Ripper**: write a short lowercase identifier of the format to `/app/hash_format.txt`.

The token starts with a `$` marker, then the scheme name run up to the next `$`, e.g. `$apr1$salt$base64hash`. In John the Ripper this family is called **Apache MD5 (apr1)**. Acceptable identifiers for `/app/hash_format.txt` are any of:
`apr1`, `apache_md5`, `md5crypt-apr1`, `apache-md5`.

Example commands you might use:

```bash
awk -F: '{print $2}' /app/secrets.htpasswd > /app/extracted_hash.txt
john --list=formats | grep -i apr   # to see how John names the format
```

After finishing, both files must exist: `/app/extracted_hash.txt` with the exact token from the file, and `/app/hash_format.txt` with one of the accepted identifiers.