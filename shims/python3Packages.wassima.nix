# wassima: create_default_ssl_context() and generate_ca_bundle() (what niquests uses) load
# root_der_certificates(): the PEM files of the OS store (/etc/ssl, /etc/pki, ...), plus the embedded
# CCADB list of wassima/_os/_embed.py (the file the fix rewires to cacert) when the OS store is empty,
# or "stale": its newest mtime is more than 3 years old. On NixOS every file there resolves into the
# store (mtime 1), so the embedded list is always merged in. The shim prints the sizes, then does one
# GET with urllib and wassima's context. In a behavioral cell the sandbox has no /etc/ssl, so the
# embedded list alone decides; on the host (ca-live-check) it is merged with the host's store.
{ pkg, ... }:
{
  inputs = [ (pkg.pythonModule.withPackages (_: [ pkg ])) ];
  script = ''
    exec python3 -I - "$URL" <<'PY'
    import sys, urllib.request
    import wassima
    from wassima._os import _embed, _linux
    os_store = _linux.root_der_certificates()
    print("wassima", wassima.__version__, "os store", len(os_store), "stale", _linux.is_trust_store_stale(),
          "embedded", len(_embed.root_der_certificates()), "used", len(wassima.root_der_certificates()), flush=True)
    ctx = wassima.create_default_ssl_context()
    with urllib.request.urlopen(sys.argv[1], context=ctx, timeout=10) as r:
        print("status", r.status)
    PY
  '';
}
