# python3Packages.raven, wheel in the `dist` output (`--shim python-wheel-raven`): the request of
# python3Packages.raven.nix (HTTPTransport with the default CA_BUNDLE, certifi not importable,
# ssl.wrap_socket restored for Python >= 3.12) against the pip-installed wheel, via python-wheel.nix.
# raven/data/cacert.pem in the wheel is the file the build copied from the source tree, so this
# separates a postPatch fix (the wheel is built with cacert's bundle) from a postInstall one
# (the wheel keeps the vendored file).
args:
import ./python-wheel.nix (
  args
  // {
    module = "raven";
    prelude = ''
      import importlib.util, os, ssl
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
    '';
    snippet = ''
      from raven.conf import defaults
      from raven.transport.http import HTTPTransport
      print("CA_BUNDLE =", defaults.CA_BUNDLE, "->", os.path.realpath(defaults.CA_BUNDLE))
      t = HTTPTransport(timeout=10)
      print("verify_ssl", t.verify_ssl, "ca_certs", t.ca_certs)
      resp = t.send(sys.argv[1], None, {})
      print("status", resp.getcode())
    '';
  }
)
