#!/usr/bin/env python3
"""Print "<SHA-256 fingerprint>\t<subject>" for every certificate in the given PEM files.

Handles CERTIFICATE and OpenSSL TRUSTED CERTIFICATE blocks (only the leading certificate
TLV is hashed, so the fingerprint ignores trust-rule aux data). One process for a whole
bundle: forking openssl per certificate is far too slow on a loaded build machine.
Stdlib only; run with `python3 -I`.
"""
import base64
import hashlib
import re
import sys

PEM = re.compile(rb"-----BEGIN (?:TRUSTED )?CERTIFICATE-----(.*?)-----END (?:TRUSTED )?CERTIFICATE-----", re.S)
ATTRS = {b"\x55\x04\x06": "C", b"\x55\x04\x0a": "O", b"\x55\x04\x0b": "OU", b"\x55\x04\x03": "CN"}


def tlv(b, i):
    tag, ln = b[i], b[i + 1]
    i += 2
    if ln & 0x80:
        n = ln & 0x7F
        ln = int.from_bytes(b[i:i + n], "big")
        i += n
    return tag, i, i + ln


def subject(der):
    try:
        _, s, _ = tlv(der, 0)  # Certificate
        _, i, _ = tlv(der, s)  # TBSCertificate
        if der[i] == 0xA0:
            i = tlv(der, i)[2]  # [0] version
        for _ in range(4):  # serial, signature, issuer, validity
            i = tlv(der, i)[2]
        _, j, end = tlv(der, i)  # subject Name
        parts = []
        while j < end:
            _, k, rdn_end = tlv(der, j)
            j = rdn_end
            while k < rdn_end:
                _, a, k = tlv(der, k)
                _, o1, o2 = tlv(der, a)
                vt, v1, v2 = tlv(der, o2)
                key = ATTRS.get(der[o1:o2])
                if key:
                    raw = der[v1:v2]
                    val = raw.decode("utf-16-be", "replace") if vt == 0x1E else raw.decode("utf-8", "replace")
                    parts.append(f"{key}={val}")
        return ", ".join(parts) or "?"
    except Exception:
        return "?"


def main():
    for path in sys.argv[1:]:
        data = open(path, "rb").read()
        for m in PEM.finditer(data):
            body = b"".join(l for l in m.group(1).splitlines() if b":" not in l)
            try:
                der = base64.b64decode(body)
                _, _, end = tlv(der, 0)
            except Exception:
                continue
            cert = der[:end]
            print(f"{hashlib.sha256(cert).hexdigest().upper()}\t{subject(cert)}")


main()
