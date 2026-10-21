# h2o: bin/h2o-httpclient (src/httpclient.c) loads "$H2O_ROOT/share/h2o/ca-bundle.crt", where
# H2O_ROOT is an environment override (unset in the cell) or the compiled-in CMAKE_INSTALL_PREFIX,
# i.e. $out. Peer verification is on unless -k is given (SSL_VERIFY_PEER |
# SSL_VERIFY_FAIL_IF_NO_PEER_CERT), and the hostname is checked after the handshake. A failed chain
# is reported as "h2o-httpclient: <X509_verify_cert_error_string>" (exit 1), before any response.
# The same file is the h2o server's default proxy.ssl.cafile. The package declares `cacert`:
# default injection.
#
# Success is the response status line, not the exit code. The harness's `openssl s_server -www`
# answers HTTP/1.0 without Content-Length and ends with a TLS close_notify, and h2o-httpclient
# does not take that as the end of the body: it exits 1 with "I/O timeout" after a verified 200,
# or (about 1 run in 6, reproduced outside the sandbox) hangs past its own --io-timeout. Hence the
# outer `timeout`, and the status line, which is printed only after the verified handshake.
{ pkg, pkgs, ... }:
{
  inputs = [
    pkg
    pkgs.gnugrep
  ];
  script = ''
    echo "ca-bundle.crt -> $(readlink -f "$PKG/share/h2o/ca-bundle.crt")"
    rc=0
    timeout 10 h2o-httpclient --io-timeout 2000 -o /dev/null "$URL" > "$TMPDIR/h2o.log" 2>&1 || rc=$?
    cat "$TMPDIR/h2o.log"
    echo "h2o-httpclient exit $rc"
    grep -Eq '^HTTP/[0-9.]+ 200( |$)' "$TMPDIR/h2o.log"
    echo "status 200 received after the verified handshake"
  '';
}
