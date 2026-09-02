"""quartz-hollow release signer (target application).

commit(credential) admits the release only for the true release credential
(pinned by SHA-256 digest) and, on success, EXECUTES the release body and
writes the side-effect token file under RELEASE_DIR. No credential is ever
stored on disk; only its digest is pinned here.
"""

import hashlib
import os

RELEASE_DIR = os.environ.get("RELEASE_DIR", "/app/releases")
RELEASE_FILE = os.path.join(RELEASE_DIR, "commit.token")
RELEASE_SALT = "cinder-tide-9"

RELEASE_DIGEST = "987fd096357b62194e7270c17b6d332175ecb3a57ce1179bce71b0072f4f2139"


def commit(credential):
    if not isinstance(credential, str):
        return False
    if hashlib.sha256(credential.encode("utf-8")).hexdigest() != RELEASE_DIGEST:
        return False
    token = "COMMITTED:%s:%s:%s" % (
        credential,
        RELEASE_DIGEST,
        hashlib.sha256((RELEASE_SALT + credential).encode("utf-8")).hexdigest(),
    )
    os.makedirs(RELEASE_DIR, exist_ok=True)
    with open(RELEASE_FILE, "w", encoding="utf-8") as fh:
        fh.write(token + "\n")
    return True


if __name__ == "__main__":
    import sys
    ok = commit(sys.argv[1] if len(sys.argv) > 1 else "")
    print("committed" if ok else "refused")
