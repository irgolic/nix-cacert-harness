# julia-bin (generic-bin.nix, shared by every julia_*-bin): NetworkOptions.ca_roots_path() is, in
# order, $JULIA_SSL_CA_ROOTS_PATH, $SSL_CERT_FILE, $SSL_CERT_DIR, the first existing system bundle
# (/etc/ssl/cert.pem, /etc/ssl/certs/ca-certificates.crt, ...), else the bundled
# share/julia/cert.pem. The cell has no env vars and no /etc/ssl, so Julia uses the bundled file,
# which is the one the fix replaces. Downloads.jl (libcurl) gets that path as its CA file.
# The package declares `cacert`: default injection.
{ pkg, ... }:
{
  inputs = [ pkg ];
  script = ''
    julia --startup-file=no --history-file=no -e '
      using NetworkOptions, Downloads
      p = NetworkOptions.ca_roots_path()
      println("ca_roots_path() = ", p, " -> ", realpath(p))
      r = Downloads.request(ARGS[1]; output = devnull)
      println("status ", r.status)
      r.status == 200 || exit(1)
    ' "$URL"
  '';
}
