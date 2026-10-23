# renpy, for bin/ca-live-check only (shims/live/ is not picked up by ca-check's behavioral matrix).
# bin/renpy runs the engine on nixpkgs' python312, whose requests uses nixpkgs' certifi (cacert).
# The vendored lib/python3.12/certifi/cacert.pem belongs to the SDK's bundled interpreter
# (lib/py3-linux-x86_64/python, from the upstream SDK tarball), which the launcher's "Build
# Distributions" copies into every Linux/Windows/macOS game it packages; renpy.fetch() and the
# updater use requests with certifi there. The shim runs that bundled interpreter (unpatched ELF,
# so through nixpkgs' dynamic loader; it needs only glibc and libgcc_s) and does one requests.get,
# i.e. what a distributed game does. Its compiled-in OpenSSL default paths point into the upstream
# build tree, so the host's /etc/ssl is not consulted.
{ pkgs, ... }:
let
  libPath = pkgs.lib.makeLibraryPath [ pkgs.glibc pkgs.stdenv.cc.cc.lib ];
in
{
  inputs = [ ];
  script = ''
    exec ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 --library-path ${libPath} \
      "$PKG/share/renpy/lib/py3-linux-x86_64/python" -EO - "$URL" <<'PY'
    import os, sys
    import certifi, requests
    print("bundled python", sys.version.split()[0], "certifi.where() =", certifi.where(), "->", os.path.realpath(certifi.where()), flush=True)
    r = requests.get(sys.argv[1], timeout=10)
    print("status", r.status_code)
    PY
  '';
}
