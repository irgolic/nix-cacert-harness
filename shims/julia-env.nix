# Shared by julia-ssl-cert-file*.nix (use with --shim and --sides before): the env-var path of
# NetworkOptions.ca_roots_path(). The package's julia runs with SSL_CERT_FILE set to a bundle of
# THIS CELL's cacert ($CACERT: stock cacert, or cacert + test root), the way a nix-shell with
# cacert (its setup hook exports SSL_CERT_FILE=<cacert>/etc/ssl/certs/ca-bundle.crt) or a NixOS
# host (/etc/ssl/certs/ca-bundle.crt, found by the system path search) hands Julia the bundle.
# SSL_CERT_FILE wins over share/julia/cert.pem, so on the before side (the unmodified julia-bin,
# injection NO-OP) the expected matrix is stock REFUSED, test CONNECTED if Julia's TLS stack can
# read that bundle. 1.13: libcurl + OpenSSL 3; 1.10: libcurl + mbedTLS 2.28.
#   bundle      file under $CACERT/etc/ssl/certs
#   trustedOnly keep only the "BEGIN TRUSTED CERTIFICATE" blocks of it (drops the plain copies
#               that buildcatrust writes next to every TLS root), to test the trust-rule FORMAT
#   emailOnlyTestRoot  append the test root as a TRUSTED block trusted for emailProtection only
#               and no plain copy, the shape of cacert's 49 e-mail-only roots in ca-bundle.crt;
#               the stock cell then tells whether such a root is (wrongly) trusted for TLS
{ pkg, pkgs, ... }:
{
  bundle ? "ca-bundle.crt",
  trustedOnly ? false,
  emailOnlyTestRoot ? false,
}:
{
  inputs = [ pkg pkgs.gawk pkgs.gnugrep ] ++ pkgs.lib.optional emailOnlyTestRoot pkgs.openssl;
  script = ''
    b=$CACERT/etc/ssl/certs/${bundle}
    ${pkgs.lib.optionalString trustedOnly ''
      awk '/^-----BEGIN TRUSTED CERTIFICATE-----$/{p=1} p{print} /^-----END TRUSTED CERTIFICATE-----$/{p=0}' \
        "$b" > "$TMPDIR/trusted-only.crt"
      b=$TMPDIR/trusted-only.crt
    ''}
    ${pkgs.lib.optionalString emailOnlyTestRoot ''
      { cat "$b"; echo "test root, TRUSTED block for emailProtection only";
        openssl x509 -in ${../fixtures/root.pem} -addtrust emailProtection -trustout; } > "$TMPDIR/email-only.crt"
      b=$TMPDIR/email-only.crt
      openssl x509 -in ${../fixtures/root.pem} -addtrust emailProtection -noout -text | grep -A1 "Trusted Uses"
    ''}
    echo "SSL_CERT_FILE=$b: $(grep -c -- '^-----BEGIN CERTIFICATE-----$' "$b" || true) plain blocks, $(grep -c -- '^-----BEGIN TRUSTED CERTIFICATE-----$' "$b" || true) TRUSTED blocks"
    export SSL_CERT_FILE=$b
    julia --startup-file=no --history-file=no -e '
      using NetworkOptions, Downloads
      p = NetworkOptions.ca_roots_path()
      println("julia ", VERSION, ": ca_roots_path() = ", p)
      r = Downloads.request(ARGS[1]; output = devnull)
      println("status ", r.status)
      r.status == 200 || exit(1)
    ' "$URL"
  '';
}
