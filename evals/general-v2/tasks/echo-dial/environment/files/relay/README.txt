SHAO relay notes (echo-dial)

The encrypted call-detail nodes live here. Follow the scheme exactly.

Naming convention
  A real encoded node is named   encoded_<X>   where <X> is the URL-safe,
  unpadded base64 of the ORIGINAL filename (e.g. the node for a file called
  "netlog.txt" is encoded_<base64 of the text netlog.txt>). To recover the
  original filename, decode <X> with URL-safe base64 after padding the segment
  back to a multiple of 4 with '=' characters. Only names that match this exact
  convention are registered nodes; everything else is unrelated and must be
  ignored.

Node body
  The body is a single line of ordinary (padded) base64. Decode it to bytes,
  then XOR each byte with the password key bytes repeated:
      plaintext = cipher XOR bytes(password)*repeated
  Decode the result as UTF-8.

Password
  The shared key is the ASCII string  ardelle

The secret word
  Exactly one node's plaintext carries the line
        :::: VAULT-VERDICT :::: <TOKEN>
  The single secret word is <TOKEN> normalised: lowercase it and drop every
  non-alphanumeric character. Only that word counts.

Output contract (see the task brief for exact paths and file names).