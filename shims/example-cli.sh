# UNTESTED example.
# Example plain-shell shim (shims/<attr>.sh): $PKG/bin is on PATH; exit 0 iff the program
# fetched $URL over a *verified* TLS connection. Available: $URL $HOST $PORT $PKG $CACERT.
# e.g. for nmap's ncat:
ncat --ssl --ssl-verify "$HOST" "$PORT" <<<"GET / HTTP/1.0
"
