"""Pick one identity (private key + certificate) out of an `openssl pkcs12 -nodes` dump.

Usage: select_p12_identity.py ALL_PEM IDENTITY_NAME KEY_OUT CERT_OUT

A keychain export holds every identity; the key and certificate of one identity
share a localKeyID bag attribute, and the certificate's friendlyName is the
identity's name.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

BLOCK = re.compile(
    r"Bag Attributes\n(?P<attrs>(?:    [^\n]*\n)+)(?:(?!-----BEGIN )[^\n]*\n)*?"
    r"(?P<pem>-----BEGIN (?P<kind>[A-Z ]+)-----\n.*?-----END (?P=kind)-----\n)",
    re.S,
)


def attribute(attrs: str, name: str) -> str | None:
    match = re.search(rf"^\s*{name}: (.+)$", attrs, re.M)
    return match.group(1).strip() if match else None


def main(all_pem: str, identity: str, key_out: str, cert_out: str) -> None:
    blocks = list(BLOCK.finditer(Path(all_pem).read_text()))
    certs = [
        b
        for b in blocks
        if "CERTIFICATE" in b["kind"] and attribute(b["attrs"], "friendlyName") == identity
    ]
    # The keychain may hold the same identity twice; identical copies are one.
    certs = list({b["pem"]: b for b in certs}.values())
    if len(certs) != 1:
        raise SystemExit(f"expected one certificate named {identity!r}, found {len(certs)}")
    key_id = attribute(certs[0]["attrs"], "localKeyID")
    keys = [
        b
        for b in blocks
        if "PRIVATE KEY" in b["kind"] and attribute(b["attrs"], "localKeyID") == key_id
    ]
    keys = list({b["pem"]: b for b in keys}.values())
    if len(keys) != 1:
        raise SystemExit(f"expected one private key for {identity!r}, found {len(keys)}")
    Path(key_out).write_text(keys[0]["pem"])
    Path(cert_out).write_text(certs[0]["pem"])


if __name__ == "__main__":
    main(*sys.argv[1:])
