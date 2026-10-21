# raven (legacy Sentry client): raven/conf/defaults.py sets CA_BUNDLE = certifi.where() when
# certifi is importable, else raven/data/cacert.pem (the vendored file the fix replaces).
# HTTPTransport (the default sync+https transport) passes that as `ca_certs` with
# verify_ssl=True. The interpreter has raven only (its flask/blinker extras are optional and
# not included), so certifi is not importable and the vendored path is what decides; the
# snippet checks this.
# raven.utils.http.urlopen still calls ssl.wrap_socket(sock, ca_certs=..., cert_reqs=...),
# which Python removed in 3.12. Without help, the verified path raises AttributeError on
# every python3 in nixpkgs, so the snippet restores ssl.wrap_socket with the semantics of the
# removed stdlib function (a context with the given verify mode and CA file, no hostname
# check) before raven is imported. Everything else is raven's own code.
{ pkg, ... }:
{
  inputs = [ (pkg.pythonModule.withPackages (_: [ pkg ])) ];
  script = ''
    exec python3 -I - "$URL" <<'PY'
    import importlib.util, os, ssl, sys
    if importlib.util.find_spec("certifi") is not None:
        sys.exit("certifi is importable: raven would use certifi.where(), not its own bundle")
    if not hasattr(ssl, "wrap_socket"):
        def wrap_socket(sock, ca_certs=None, cert_reqs=ssl.CERT_NONE, **kw):
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ctx.check_hostname = False
            ctx.verify_mode = cert_reqs
            if ca_certs:
                ctx.load_verify_locations(ca_certs)
            return ctx.wrap_socket(sock)
        ssl.wrap_socket = wrap_socket
    import raven
    from raven.conf import defaults
    from raven.transport.http import HTTPTransport
    print("raven", raven.VERSION, "CA_BUNDLE =", defaults.CA_BUNDLE, "->", os.path.realpath(defaults.CA_BUNDLE))
    t = HTTPTransport(timeout=10)
    print("verify_ssl", t.verify_ssl, "ca_certs", t.ca_certs)
    resp = t.send(sys.argv[1], None, {})
    print("status", resp.getcode())
    PY
  '';
}
